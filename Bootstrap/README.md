# One-time GitHub OIDC prerequisite

The existing bootstrap state owns the S3 state bucket and DynamoDB lock table.
It now also owns GitHub OIDC, an application-deployment role, and a separate
Terraform infrastructure role. It does not create the VPC, ECS, RDS or other
application resources. Those are deployed exclusively by the gated workflow.

Trust is restricted to Dcoder21/SentinelPay-Final-solution on main. The numeric
owner/repository IDs were obtained from GitHub's API, and are configurable
bootstrap variables. Both legacy and immutable subject formats are accepted.
Do not add a GitHub environment to the deployment job without changing trust:
environment-based jobs have a different OIDC subject.

With your existing local AWS CLI credentials, from the repository root:

```powershell
terraform -chdir=Bootstrap init
terraform -chdir=Bootstrap plan -input=false "-out=oidc-bootstrap.tfplan"
terraform -chdir=Bootstrap show -no-color oidc-bootstrap.tfplan
# Review this one-time prerequisite plan before applying it:
terraform -chdir=Bootstrap apply oidc-bootstrap.tfplan
terraform -chdir=Bootstrap output -raw github_infrastructure_role_arn
```

Set that ARN as the GitHub repository variable `AWS_INFRA_ROLE_ARN` under
Settings > Secrets and variables > Actions > Variables. No AWS access keys
need to be stored in GitHub. `github_application_role_arn` is for a future
image/ECS deployment workflow, not this infrastructure workflow.

The infrastructure role grants provisioning permissions for the stack's AWS
services in eu-west-1, project-prefixed S3 buckets and IAM workload roles, and
the specific dev state object/lock table. Service permissions are broad within
the region to support resource creation and AWS API operations that do not
support resource scoping. Treat main/workflow modifications as privileged.
The role is explicitly denied access to modify/pass the bootstrap identities
and OIDC provider. It cannot delete the bootstrap bucket or lock table.

Keep Bootstrap's local state backed up securely. Do not commit state or AWS
credentials. If GitHub OIDC already exists in your AWS account, import its ARN
into `module.github_oidc.aws_iam_openid_connect_provider.github` rather than
creating a duplicate. If a previous dev deployment already owns OIDC/roles,
move/import those resources into bootstrap before applying: this workspace
had no dev state when this separation was made.

After bootstrap, push the code to main. The workflow waits for every gate,
authenticates through OIDC, plans the dev stack, enforces OPA against that plan,
and applies the exact saved plan. Pull requests never deploy or obtain AWS
credentials. Plans/state are not uploaded as GitHub artifacts.

Protect main with a GitHub ruleset requiring the CI checks and review, and
disable force pushes. Workflow gates control this pipeline; they cannot
prevent a separately authorized AWS administrator from deploying manually.
