"""Publish the already-scanned images, migrate, and roll out ECS services."""
import json
import os
import subprocess
import time

REGION = "eu-west-1"
ROOT = "infra/environments/dev"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def aws(*args):
    return json.loads(run("aws", *args, "--region", REGION, "--output", "json"))


def output(name):
    return json.loads(run("terraform", f"-chdir={ROOT}", "output", "-json", name))


def main():
    sha = os.environ["GITHUB_SHA"]
    repositories = output("ecr_repository_urls")
    registry = repositories["payments-api"].split("/")[0]
    token = run("aws", "ecr", "get-login-password", "--region", REGION)
    subprocess.run(["docker", "login", "--username", "AWS", "--password-stdin", registry], input=token, text=True, check=True)
    subprocess.run(["docker", "load", "-i", "scanned-images.tar"], check=True)
    for service, local in [("payments-api", "payments"), ("kyc-api", "kyc")]:
        remote = repositories[service] + ":" + sha
        # Reruns reuse immutable images from this commit rather than overwriting.
        image = subprocess.run(["aws", "ecr", "describe-images", "--region", REGION,
            "--repository-name", repositories[service].split("/", 1)[1], "--image-ids", "imageTag=" + sha], capture_output=True)
        if image.returncode:
            subprocess.run(["docker", "tag", "sentinelpay-" + local + ":" + sha, remote], check=True)
            subprocess.run(["docker", "push", remote], check=True)
    cluster = output("ecs_cluster")
    network = {"awsvpcConfiguration": {"subnets": output("private_subnets"),
        "securityGroups": [output("ecs_security_group")], "assignPublicIp": "DISABLED"}}
    result = aws("ecs", "run-task", "--cluster", cluster, "--launch-type", "FARGATE",
        "--task-definition", output("migration_task"), "--network-configuration", json.dumps(network))
    if result.get("failures") or not result.get("tasks"):
        raise RuntimeError("Migration task could not be started: " + json.dumps(result.get("failures")))
    task = result["tasks"][0]["taskArn"]
    for _ in range(90):
        detail = aws("ecs", "describe-tasks", "--cluster", cluster, "--tasks", task)["tasks"][0]
        if detail["lastStatus"] == "STOPPED":
            if any(c.get("exitCode", -1) != 0 for c in detail["containers"]):
                raise RuntimeError("Migration failed; inspect the migration CloudWatch log. " + detail.get("stoppedReason", ""))
            break
        time.sleep(10)
    else:
        raise RuntimeError("Migration did not finish within 15 minutes")
    services = output("application_deployment")
    for config in services.values():
        aws("ecs", "update-service", "--cluster", cluster, "--service", config["service"],
            "--task-definition", config["task_definition"], "--desired-count", "1")
    for _ in range(120):
        details = aws("ecs", "describe-services", "--cluster", cluster, "--services", *[c["service"] for c in services.values()])
        ready = True
        for service in details["services"]:
            expected = next(c["task_definition"] for c in services.values() if c["service"] == service["serviceName"])
            deployments = service["deployments"]
            primary = next(d for d in deployments if d["status"] == "PRIMARY")
            if primary.get("rolloutState") == "FAILED" or primary["taskDefinition"] != expected:
                raise RuntimeError("ECS deployment failed or rolled back: " + service["serviceName"])
            ready &= len(deployments) == 1 and primary.get("rolloutState") == "COMPLETED" and service["runningCount"] == 1
        if ready and len(details["services"]) == 2:
            print("Both application services are running the scanned commit.")
            return
        time.sleep(10)
    raise RuntimeError("Application rollout did not stabilize within 20 minutes")


if __name__ == "__main__":
    main()
