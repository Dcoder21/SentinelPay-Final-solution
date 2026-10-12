# SentinelPay testing deployment

This deploys the current payments and KYC APIs for testing. It does not process real payments or perform external identity verification. No provider credentials are configured; BVN routes still require a real upstream provider before they can work.

## Endpoint and networking

API Gateway supplies an AWS-managed HTTPS execute-api address in eu-west-1, without a purchased domain, DNS change, or customer ACM certificate. A VPC link connects to an internal ALB; the ALB accepts port 80 only from the VPC link security group. Both Fargate services, PostgreSQL and Redis stay in private subnets. WAF remains associated with the ALB. Private backend HTTP has narrow scanner annotations documenting where public TLS terminates. OPA now rejects all world-open security group ingress, including ports 80 and 443.

## Pipeline sequence

Every security, validation, application and policy job must succeed before the deployment job receives AWS OIDC credentials. Images are built, scanned for HIGH/CRITICAL vulnerabilities, and tested with PostgreSQL and Redis. Successful images are saved as a one-day GitHub artifact. Deployment downloads those same images and publishes them to immutable ECR commit tags, without rebuilding.

Terraform plans against the remote backend, OPA checks that exact plan, and the workflow applies the saved plan. New ECS services start with zero tasks while repositories and secrets are provisioned. The workflow then publishes images, runs the schema migration, and rolls out both services. Terraform deliberately ignores service task-definition and desired-count drift because the gated application rollout owns those fields. No plan files or state are uploaded as artifacts.

Registration/login and an authenticated KYC lookup verify HTTPS, routing, PostgreSQL, Redis and shared JWT keys after rollout. Verification creates a synthetic merchant under example.invalid, without payment balances or identity documents. Tests must not use real customer information.

## Secrets and database

RSA JWT keys, database application password, rate-limit key and session key are generated in Terraform and stored in KMS-encrypted Secrets Manager. Sensitive values also exist in the encrypted remote Terraform state, whose IAM access must stay restricted. Nothing should be copied into GitHub secrets or tfvars. Secrets are injected by the ECS execution role; KYC receives only the public JWT key. Its runtime role can read/write its KYC object prefix. Database migration uses the RDS managed administrator secret; the APIs use a separate non-admin database login. Schema migration is idempotent and does not insert the local demo accounts or MD5 passwords. RDS connections use verify-full TLS with the AWS RDS CA bundle; managed Redis uses certificate-verified TLS.

## Configuration and operations

Versioned non-secret inputs live in infra/environments/dev/terraform.tfvars.example. GitHub supplies TF_VAR_image_tag from the commit. AWS_INFRA_ROLE_ARN is the repository variable for the bootstrap role. The bootstrap IAM policy gained API Gateway provisioning permission; bootstrap changes are identity prerequisites, not application deployment.

Watch the SentinelPay CI run on main. Never apply application Terraform locally to work around a failed gate. Failed migrations stop the rollout; ECS circuit breakers stop failed application deployments. Inspect /ecs/sentinelpay-dev CloudWatch logs and ECS service events when troubleshooting. API URL appears in Terraform outputs and successful verification logs.

This is a single-region development/testing stack with billable NAT, ALB, RDS and Redis resources. Cross-region disaster recovery and secret rotation for generated application keys are not configured. Moving to real payment/customer traffic requires provider integration and a separate readiness review.
