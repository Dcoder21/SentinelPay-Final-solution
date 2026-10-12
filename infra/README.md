# Gated AWS deployment

Application infrastructure is deployed by `.github/workflows/ci.yml` only after
all required gates pass. Do not run local `terraform apply` for this stack.
The one-time OIDC/backend prerequisite is documented in `Bootstrap/README.md`.

## First setup

1. Review and apply only the bootstrap prerequisite plan using your existing
   local AWS credentials. It owns state storage and GitHub identity, not workloads.
2. Add its `github_infrastructure_role_arn` output as the GitHub repository
   variable `AWS_INFRA_ROLE_ARN` in Dcoder21/SentinelPay-Final-solution.
3. Commit the workflow, Terraform sources and both `.terraform.lock.hcl` files.
   Do not commit Terraform state, plans or credentials.
4. Push to main and inspect the workflow in GitHub Actions.

The dev remote backend already references the bootstrap bucket in eu-west-1.
`terraform.tfvars.example` is the versioned, non-secret configuration used by
GitHub. The workflow copies it into the Git-ignored `terraform.tfvars`.
Edit the example for pipeline deployment changes; local tfvars edits alone
will not affect GitHub deployment.

## Deployment sequence

Gitleaks, Bandit, Semgrep, dependency/image Trivy scans, Checkov, tfsec,
application smoke tests, Terraform format/validation, and pipeline/OPA
regression tests run before the deploy job. Existing scanner severity thresholds
and documented exceptions remain the configured gate criteria.

Only a successful main push in the intended repository can enter the deploy
job. It authenticates with OIDC, initializes the remote backend, creates a
saved Terraform plan, runs Conftest against its JSON using all policy namespaces,
and applies that same saved plan. OPA failures stop apply. Deployment runs are
serialized and a newer push does not cancel an active apply. The job then checks
ECS stability and the Nginx endpoint. Pull requests never obtain AWS credentials
or deploy. Plans/state are not uploaded as artifacts because they may contain secrets.

OPA now checks the actual AWS ingress-rule resource type and JSON-string IAM
policies, alongside the original fixtures. HTTP is an explicit dev smoke-test
exception; public SSH/other workload ingress is rejected.

## Current smoke test and later application deployment

The stack creates an internet-facing WAF-protected ALB, private ECS tasks,
private PostgreSQL 17/RDS with managed master-password rotation, Redis,
encrypted application storage, ECR repositories and detection resources.
AWS-compatible log delivery uses SSE-S3; application data remains KMS-encrypted.
ECS HTTPS image pulls use NAT. The containment responder has separate API
connectivity from the isolation security group. Its existing signing mode
remains Warn; signed responder artifacts are a later hardening step.

The current image is Nginx. This tests infrastructure, not the payments/KYC APIs.
Those still need service task definitions, secrets, runtime roles, routing,
database/Redis configuration and migrations.

HTTP smoke-test mode is allowed only for dev. Do not send credentials, customer
data or payment requests over it. For TLS, DNS-validate an ACM certificate in
eu-west-1, set its ARN in the versioned example, disable HTTP smoke-test mode,
and let the pipeline deploy the change. Point your domain at the ALB.
Disabling public HTTPS egress requires private registry/API endpoints and rules.

## Diagnose after a workflow run

```powershell
terraform -chdir=infra/environments/dev init
terraform -chdir=infra/environments/dev output
$ecsCluster = terraform -chdir=infra/environments/dev output -raw ecs_cluster
$ecsService = terraform -chdir=infra/environments/dev output -raw ecs_service
aws ecs describe-services --region eu-west-1 --cluster $ecsCluster --services $ecsService --query "services[0].{Running:runningCount,Desired:desiredCount,Events:events[0:5]}"
```

Use AWS console target health and CloudWatch logs if tasks do not stabilize.
The `database_secret_arn` output identifies RDS-managed credentials; keep values
out of GitHub logs. The separate application role from bootstrap is reserved
for a future image/ECS deployment workflow.

Protect main with required checks/reviews and no force pushes. Workflow gating
does not remove an AWS administrator's ability to deploy outside GitHub.
The stack incurs charges including NAT, ALB, Multi-AZ RDS, Redis, WAF and security
services. Deletion protection and retention require deliberate cleanup.
