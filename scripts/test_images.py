"""Test the exact deployment images with PostgreSQL, Redis, and shared JWTs."""
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import urllib.request
from verify_deployment import verify


def docker(*args):
    subprocess.run(["docker", *args], check=True, stdout=subprocess.DEVNULL)


def main():
    sha = os.environ["GITHUB_SHA"]
    password = secrets.token_urlsafe(32)
    app_password = secrets.token_urlsafe(32)
    names = ["test-payments", "test-kyc", "test-postgres", "test-redis"]
    docker("network", "create", "sentinelpay-test")
    try:
        with tempfile.TemporaryDirectory() as temp:
            private = Path(temp) / "private.pem"
            public = Path(temp) / "public.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048", "-out", str(private)], check=True, stderr=subprocess.DEVNULL)
            subprocess.run(["openssl", "pkey", "-in", str(private), "-pubout", "-out", str(public)], check=True)
            def envfile(name, values):
                file = Path(temp) / name
                # Docker env-file cannot contain multiline PEMs; applications accept escaped newlines below.
                file.write_text("\n".join(k + "=" + v.replace("\n", "\\n") for k,v in values.items()) + "\n")
                file.chmod(0o600)
                return str(file)
            master = envfile("postgres.env", {"POSTGRES_USER": "sentinelpay_admin", "POSTGRES_PASSWORD": password, "POSTGRES_DB": "sentinelpay"})  # gitleaks:allow disposable generated test password, no embedded credential
            docker("run", "-d", "--name", "test-postgres", "--network", "sentinelpay-test", "--env-file", master, "postgres:17-alpine")
            docker("run", "-d", "--name", "test-redis", "--network", "sentinelpay-test", "redis:7-alpine")
            for _ in range(30):
                if subprocess.run(["docker", "exec", "test-postgres", "pg_isready", "-U", "sentinelpay_admin"], stdout=subprocess.DEVNULL).returncode == 0:
                    break
                time.sleep(2)
            migration = envfile("migration.env", {"DATABASE_URL": f"postgresql://sentinelpay_admin:{password}@test-postgres/sentinelpay", "APP_DB_PASSWORD": app_password})  # gitleaks:allow URL interpolates a generated disposable test password
            docker("run", "--rm", "--network", "sentinelpay-test", "--env-file", migration, "sentinelpay-payments:" + sha, "python", "-m", "app.migrate")
            common = {"DATABASE_URL": f"postgresql://sentinelpay_app:{app_password}@test-postgres/sentinelpay", "JWT_PUBLIC_KEY": public.read_text(), "AWS_REGION": "eu-west-1", "AWS_EC2_METADATA_DISABLED": "true"}  # gitleaks:allow URL interpolates a generated disposable test password
            payments = envfile("payments.env", dict(common, JWT_PRIVATE_KEY=private.read_text(), RATE_LIMIT_KEY_SECRET=secrets.token_urlsafe(32), SESSION_SIGNING_KEY=secrets.token_urlsafe(32), RATELIMIT_STORAGE_URI="redis://test-redis:6379/2"))
            kyc = envfile("kyc.env", common)
            for service, env, port in [("payments", payments, 8001), ("kyc", kyc, 8002)]:
                docker("run", "-d", "--read-only", "--name", "test-" + service, "--network", "sentinelpay-test", "--env-file", env, "-p", f"127.0.0.1:{port}:{port}", "sentinelpay-" + service + ":" + sha)
            for port in (8001,8002):
                for _ in range(30):
                    try:
                        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2):
                            break
                    except Exception:
                        time.sleep(2)
                else:
                    raise RuntimeError("Container did not become healthy")
            verify("http://127.0.0.1:8001", "http://127.0.0.1:8002")
    finally:
        subprocess.run(["docker", "rm", "-f", *names], stdout=subprocess.DEVNULL)
        subprocess.run(["docker", "network", "rm", "sentinelpay-test"], stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
