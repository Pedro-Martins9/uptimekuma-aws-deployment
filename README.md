# Uptime Kuma on AWS ECS (EC2) with Terraform

This repository provisions [Uptime Kuma](https://github.com/louislam/uptime-kuma) on Amazon ECS using EC2 capacity, an Application Load Balancer (ALB), and Terraform remote state.

> **Current state:** The application stack was deployed and tested, then destroyed to control ongoing AWS costs. The S3 Terraform state backend is intended to remain. The architecture below documents the tested deployment design; it is not a claim that the application is currently running.
>
> **Honest status:** GitHub Actions OIDC deployment, CloudWatch alarms, durable application backups, and a successful backup-restore drill are not yet complete. The proposed design and acceptance criteria are described below. No application backup has been represented as restored.

## Goals

- Learn the compute and orchestration layers by using **ECS on EC2**, not Fargate.
- Provision repeatable infrastructure with Terraform and an S3 remote state backend.
- Use an ALB, security groups, IAM roles, Systems Manager, CloudWatch logs, and ECS capacity providers.
- Keep costs down by deploying only when testing and destroying the application stack afterward.
- Extend the project with CI/CD using GitHub Actions OIDC, actionable alarms, and a backup that has actually been restored and verified.

## Tested architecture

~~~mermaid
flowchart TB
    Internet((Internet))
    Targets["Monitored websites<br/>HTTP / HTTPS egress"]
    GH["GitHub repository<br/>Terraform source"]
    OIDC["GitHub Actions OIDC<br/>short-lived AWS credentials"]
    State[("S3 Terraform state<br/>versioning + SSE-S3<br/>S3 lock file")]

    subgraph AWS["AWS eu-west-1 — deployment environment (currently torn down)"]
      subgraph VPC["VPC 10.20.0.0/16"]
        ALB["Application Load Balancer<br/>HTTP listener :80"]
        TG["Target group<br/>instance targets + health check"]
        subgraph AZA["Public subnet — eu-west-1a"]
          EC2["ECS-optimized Amazon Linux 2023<br/>EC2 instance (t3.small)"]
        end
        subgraph AZB["Public subnet — eu-west-1b"]
          Spare["Second public subnet<br/>for ALB / ASG placement"]
        end
        ECS["ECS cluster + capacity provider<br/>EC2 Auto Scaling Group (0–1)"]
        App["Uptime Kuma task<br/>container :3001<br/>bridge networking / dynamic host port"]
        Logs[("CloudWatch Logs<br/>/ecs/uptimekuma<br/>7-day retention")]
        IGW["Internet Gateway<br/>public-subnet routing"]
        ALB --> TG
        TG -->|"observed host port 32768<br/>(assigned dynamically)"| App
        ECS --> EC2
        EC2 --> App
        App --> Logs
        IGW --> Targets
        App -->|"monitor checks"| IGW
      end
    end

    Internet -->|"HTTP :80"| ALB
    GH --> OIDC -->|"Terraform API calls"| AWS
    OIDC --> State
~~~

The observed host port **32768 was a runtime assignment**, not a hard-coded task port. The task definition uses container port 3001 and host port 0, which lets ECS choose a host port and register it in the ALB target group.

The diagram describes the previously deployed stack. **It does not represent an active endpoint** following teardown.

## Architecture breakdown

### Network and request path

- One VPC with CIDR **10.20.0.0/16**.
- Two public subnets, one in **eu-west-1a** and one in **eu-west-1b**.
- An Internet Gateway and public route table with a default route to the Internet Gateway.
- An internet-facing ALB attached to both subnets.
- An HTTP listener on port 80 forwarding requests to an instance target group.
- A target-group health check against **/**, expecting HTTP 200–399.
- ECS container instances accept application ingress only from the ALB security group, on the configured dynamic host-port range **32768–65535**.
- Instance egress permits TCP 80 and 443 for website checks, image pulls, and AWS API access.

The subnets are public to avoid NAT Gateway costs in a learning deployment. The ECS instances can have public IPs, but their security group does not allow direct public inbound application access or SSH. Systems Manager Session Manager is the intended administration path.

**Known networking follow-up:** the ALB security group permits inbound TCP 443, but the deployed configuration had no HTTPS listener or ACM certificate. Port 443 permission alone does not provide TLS. Before using the service with real credentials, either configure a domain and ACM certificate with an HTTPS listener and an HTTP-to-HTTPS redirect, or remove the unused 443 ingress rule until HTTPS is ready. Do not treat the HTTP endpoint as suitable for sensitive credentials.

### Compute and orchestration

- ECS cluster: **uptimekuma-cluster**, with Container Insights enabled.
- ECS service: **uptimekuma-service**, desired count 1 during the test.
- ECS capacity provider backed by an EC2 Auto Scaling Group.
- Auto Scaling Group target range: minimum 0, maximum 1.
- Launch template selects the recommended ECS-optimized Amazon Linux 2023 AMI through an SSM public parameter.
- EC2 instance type: **t3.small**.
- ECS task: 256 CPU units and 512 MiB memory.
- Task network mode: **bridge**; container port 3001 with dynamic host-port assignment.
- EC2 container agent joins the configured ECS cluster through launch-template user data.

This choice exposes both ECS scheduling/capacity management and the EC2 layer. It is intentionally more involved than Fargate.

### Application data and logging

- The container writes its application data to **/app/data**.
- The ECS task maps that directory to the EC2 host path **/var/lib/uptimekuma**.
- Container logs are sent to CloudWatch Logs group **/ecs/uptimekuma**, with seven-day retention.

**Critical known limitation:** this host-path volume is tied to the EC2 instance's local storage. It is not durable application storage across instance replacement or termination. The deployed stack did not include an application-data backup system, and no restore drill has yet been performed. Do not describe the service as recoverable until the backup and restore work below is implemented and tested.

The configured image is **louislam/uptime-kuma:1**, a moving major-version tag. Before the next deployment, pin a specific supported release or image digest and record the chosen version.

### IAM and administration

Two separate IAM roles were configured:

- **EC2 instance role:** ECS container agent permissions plus **AmazonSSMManagedInstanceCore**.
- **ECS task execution role:** **AmazonECSTaskExecutionRolePolicy** for execution-time operations such as pulling images and publishing logs.

There was no application task role for Uptime Kuma. When an S3 backup worker is implemented, give that workload its own narrowly scoped task role; do not add backup permissions to the EC2 instance role or broadly expand the task execution role.

No inbound SSH rule was configured. Administrative access was tested through Systems Manager Run Command.

### Terraform state and bootstrap

The Terraform backend is separate from the application stack:

- S3 bucket: **REPLACE_WITH_EXISTING_TFSTATE_BUCKET**.
- State key: **uptimekuma/terraform.tfstate**.
- Region: **eu-west-1**.
- Server-side encryption: SSE-S3 (AES256).
- S3 bucket versioning enabled.
- S3 Block Public Access enabled.
- Native S3 lock file enabled with **use_lockfile = true**.
- Terraform configuration uses **prevent_destroy = true** on the state bucket resource.
- AWS provider restricts the main configuration to the intended AWS account through **allowed_account_ids**.

The one-time bucket setup lives under **terraform/bootstrap-state/**; the main application infrastructure lives under **terraform/**.

**Never run the application teardown against terraform/bootstrap-state/.** Keep the backend bucket, its versions, and the bootstrap configuration. The bootstrap configuration itself uses local Terraform state unless separately migrated, so preserve its working directory and local state file.

## What was actually tested

The following were observed during the deployment test:

- ECS service reached steady state with one running task.
- ALB target health reported **healthy**.
- ECS mapped container port 3001 to host port 32768.
- The EC2 instance ephemeral port range was **32768–60999**; the configured security group range covered the observed port.
- Systems Manager Run Command succeeded without SSH.
- CloudWatch log delivery was configured for the task.
- Terraform successfully destroyed the main application stack.

The destroy operation required intervention because ECS capacity management kept the EC2 instance at desired capacity 1 while the service was draining. The Auto Scaling Group was set to zero capacity, the instance began shutting down, and the Terraform destroy then completed. The teardown behaviour should be made more deterministic and documented in a runbook.

These checks prove the test deployment worked. They do **not** prove HTTPS, alert delivery, CI/CD deployment, durable backups, or restore recovery.

## CI/CD plan: GitHub Actions + OIDC

The repository includes two workflows:

- **.github/workflows/terraform-validate.yml** runs formatting and validation on pull requests and pushes to **main**. It requires no AWS credentials.
- **.github/workflows/terraform-deploy.yml** is **manual only**. It plans with an OIDC-backed plan role. Applying requires explicitly choosing deployment, typing **DEPLOY**, and passing the **aws-deploy** GitHub Environment gate.

This is deliberately not auto-apply-on-push. The application stack is currently destroyed to save money; a workflow deployment would recreate billable resources.

~~~mermaid
flowchart TD
  PR["Pull request / push"] --> Validate["terraform fmt + init without backend + validate"]
  Validate --> Review["Review and merge to main"]
  Review --> Manual["Manually run deploy workflow"]
  Manual --> Plan["Assume limited plan role through GitHub OIDC"]
  Plan --> Artifact["Short-lived Terraform plan artifact"]
  Artifact --> Gate{"Mode = deploy<br/>and typed DEPLOY?"}
  Gate -->|"No"| Done["Plan only; no AWS changes"]
  Gate -->|"Yes"| Approval["GitHub Environment: aws-deploy<br/>review / protection rules"]
  Approval --> Apply["Assume apply role through OIDC"]
  Apply --> Terraform["Apply the saved Terraform plan"]
  Terraform --> Verify["Verify service health and cost resources"]
~~~

### One-time GitHub and AWS setup

1. Create the AWS IAM OIDC provider for **token.actions.githubusercontent.com** if the account does not already have it. Use audience **sts.amazonaws.com**.
2. Create two IAM roles: a **plan role** and an **apply role**. Avoid long-lived AWS access keys in GitHub.
3. Restrict the plan role trust policy to the exact repository and the **main** ref. Restrict the apply role trust to the exact GitHub Environment subject, **repo:Pedro-Martins9/uptimekuma-aws-deployment:environment:aws-deploy**.
4. Add the repository variable **AWS_TERRAFORM_PLAN_ROLE_ARN** with the plan role ARN.
5. Add the environment variable **AWS_TERRAFORM_APPLY_ROLE_ARN** to the **aws-deploy** Environment with the apply role ARN.
6. Configure the **aws-deploy** Environment to allow deployments from **main**; add required reviewers if available for the account's GitHub plan.
7. Give the plan role only the resource read permissions needed by Terraform plus the S3 state/lock-file permissions Terraform needs to acquire and release its lock. Give the apply role the specific resource-management permissions needed by this configuration. Do not grant **AdministratorAccess** by default.

Example trust-policy subject conditions (replace the account placeholder in the federated provider ARN when creating the roles):

~~~json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:Pedro-Martins9/uptimekuma-aws-deployment:ref:refs/heads/main"
    }
  }
}
~~~

Use that **sub** condition for the plan role. For the apply role, use the GitHub Environment subject shown in step 3 instead. Each role's trust policy must name the actual IAM OIDC provider ARN for the account. The workflows cannot work until both role ARNs and their IAM policies are configured.

The deploy workflow stores its binary plan as a private-repository GitHub Actions artifact for one day so the approval step can apply the exact plan that was reviewed. Terraform plan files can contain sensitive data; keep the repository private, do not add secrets to Terraform state, and do not extend artifact retention unnecessarily. If state changes before the apply step, Terraform should reject the stale plan rather than apply it.

### Pipeline protections

- Pull request validation has no AWS token and no cloud permissions.
- Deployment runs only through manual dispatch from **main**.
- The plan and apply roles are different.
- AWS credentials are short-lived through OIDC; no static AWS access keys are used.
- Apply is gated by both the explicit **DEPLOY** confirmation and the protected GitHub Environment.
- Destruction remains a deliberate, separately reviewed operation; no automated workflow destroys resources.

## Monitoring and alarm roadmap

Container Insights and seven-day log retention were configured, but **CloudWatch alarms and notification delivery were not implemented**. The proposed alarms should be in Terraform and send to an SNS topic with a confirmed email subscription.

| Alarm | Proposed condition | Why it matters |
|---|---|---|
| ALB unhealthy targets | **UnHealthyHostCount >= 1** for 2 of 3 one-minute periods | Detects that requests cannot reach a healthy target. |
| ECS service below desired count | Running task count below desired count for 5 minutes | Detects failed tasks or capacity problems. Set dimensions for this cluster and service. |
| ECS CPU utilisation | Service CPU above 80% for 5 minutes | Indicates sustained CPU pressure. |
| ECS memory utilisation | Service memory above 80% for 5 minutes | Indicates memory pressure before task failure. |
| ALB 5xx responses | ALB or target 5xx count breaches a chosen threshold | Distinguishes load-balancer errors from application errors. Establish a baseline before finalising thresholds. |
| EC2 status checks | **StatusCheckFailed >= 1** | Detects underlying instance or reachability problems. |
| Backup freshness / failure | Latest-success age exceeds 26 hours, or a backup run reports failure | Detects broken backup schedules and stale recovery points. Requires a backup job and success metric first. |
| AWS budget | Alerts at 50%, 80%, and 100% of a small monthly budget | Gives early warning about accidental continuous resources. Budget notifications are cost controls, not a replacement for destroying test infrastructure. |

A key design point: Uptime Kuma cannot reliably alert you that Uptime Kuma itself is down. Use independent AWS alarms for ECS, the ALB and EC2, and use SNS email notifications that are confirmed and tested. Thresholds and alarm actions need to be verified during a real deployment.

## Backup and restore: a required proof, not a claimed accomplishment

**No application backup has yet been restored in this project.** The original host-path design means an EC2 termination can remove the only copy of the app data. A backup system and a verified restore test are required before calling this production-ready.

Proposed implementation:

1. Pin the Uptime Kuma version and verify the database path and backup procedure for that exact version.
2. Add a dedicated backup worker/sidecar that can access the same application data volume and uses SQLite's consistent online backup mechanism, rather than blindly copying a live database file.
3. Upload encrypted backup archives to a separate S3 bucket with Block Public Access, versioning, a short and explicit retention policy, and lifecycle expiry. Do not store application backups in the Terraform state bucket.
4. Give the backup workload its own task role limited to writing objects under a dedicated backup prefix. Keep restore access separate and restricted.
5. Emit success/failure metrics and the age of the most recent successful backup. Alert if backups fail or the latest success is older than the agreed recovery point objective.
6. Write and run a restore drill against an **isolated temporary deployment**, never over the live data directory.

### Restore-drill acceptance criteria

A restore is not complete just because an archive can be downloaded. The test must:

- Identify the exact S3 object version and checksum used.
- Restore into a fresh volume or isolated task.
- Run SQLite integrity checks against the restored database (for SQLite databases, verify **PRAGMA integrity_check** returns **ok**).
- Start the pinned Uptime Kuma image against the restored data.
- Confirm that expected users/settings/monitors exist and that the application health check passes.
- Record the start/end timestamps, recovery steps, observed recovery time, any lost monitoring history, and screenshots or sanitized logs in **docs/restore-drill.md**.
- Only mark the restore milestone complete after another person can follow the runbook and reproduce it.

Initial targets to validate, not guarantees: **RPO of 24 hours** (at most a day of monitoring state at risk) and **RTO under 30 minutes** for a small deployment. Tighten them only after measuring an actual restore. The app stack is currently off, so completing this drill will require a deliberate temporary deployment and may incur AWS charges.

## Future plan

### Phase 1 — make the baseline safer

- Pin a specific Uptime Kuma image version or digest.
- Fix the unused 443 security-group ingress by implementing ACM/HTTPS with a domain or removing 443 until TLS is ready.
- Revisit the host-path persistence design before relying on stored monitoring configuration.
- Add preflight / post-deployment checks and a teardown runbook for ECS draining and capacity-provider scale-in.

**Exit criteria:** repeatable deploy, healthy ALB target, successful SSM access, and predictable teardown with no unexpected resources left behind.

### Phase 2 — CI/CD with short-lived identity

- Configure GitHub's AWS OIDC provider and separate plan/apply roles.
- Protect the **aws-deploy** GitHub Environment.
- Run the validation workflow on every pull request.
- Demonstrate a manual plan with no static AWS secrets and a gated deploy of the reviewed plan.

**Exit criteria:** untrusted pull requests cannot obtain AWS credentials; deploy is explicit and audited; a plan-only run makes no changes.

### Phase 3 — alarms and cost safeguards

- Add Terraform-managed CloudWatch alarms and SNS notifications.
- Confirm the SNS email subscription and test alert delivery.
- Create a small AWS Budget with 50/80/100 percent notifications.
- Verify alarms by safely triggering test conditions and restoring normal operation.

**Exit criteria:** notification delivery observed end-to-end, no alarm merely defined but untested.

### Phase 4 — recoverable application data

- Implement scheduled SQLite-consistent backups to a dedicated S3 bucket.
- Add restricted backup and restore IAM roles, lifecycle expiration and backup freshness metrics.
- Perform and document the first isolated restore drill.
- Test recovery after replacing the EC2 host, not just restarting a container.

**Exit criteria:** a real backup has been restored successfully, the database passes integrity checks, expected Uptime Kuma state is present, and the runbook records measurable RPO/RTO.

### Phase 5 — hardening and portfolio evidence

- Add HTTPS and a domain when available.
- Review whether a private-subnet design is worth its additional NAT/VPC-endpoint costs for this low-traffic workload.
- Add Terraform static analysis and policy checks; pin GitHub Actions to commit SHAs for stronger supply-chain control.
- Add screenshots and sanitized test evidence for deployment, alarms, the OIDC workflow, and the completed restore drill.
- Publish a short architecture decision record explaining ECS on EC2 versus Fargate, public subnets versus private subnets, and cost trade-offs.

## Cost strategy

The ALB and EC2 instance generated ongoing hourly charges while deployed; public IPv4 addresses, EBS, and CloudWatch can also contribute. ECS capacity-provider scaling can launch an instance even if the ASG initially has desired capacity zero, because a service with desired count one needs compute.

For an intentional test:

1. Review the Terraform plan and expected resources before applying.
2. Deploy manually and perform the test in one session.
3. Verify the service, target health, logs, SSM access and any planned alarm/backup tests.
4. Run **terraform plan -destroy** and inspect the full plan before destroying the application stack.
5. If ECS is draining while an EC2 instance remains in service, inspect ECS tasks and ASG scaling activities. Scale the ASG to zero only as a deliberate recovery action, then resume Terraform teardown.
6. Verify no ALB, running EC2 instance, leftover EBS volume, unneeded public IPv4 address, target group, or application CloudWatch log group remains.
7. Preserve the separate S3 Terraform state backend so the stack can be recreated later.

Destroying the main stack is intentional for cost control, not a replacement for application backup. S3 state storage and historical versions still have storage/request costs.

## Deploy and destroy locally

The main application configuration is in the **terraform/** directory. Applying it can create billable resources; the stack is not intended to be continuously running.

~~~bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
# Inspect the full plan before proceeding.
terraform apply
~~~

After the test, inspect the planned removal before destroying:

~~~bash
cd terraform
terraform plan -destroy
# Review all resources and ensure the state bucket is not included.
terraform destroy
~~~

The backend bootstrap is separate and should only be run once when preparing a new AWS account/backend:

~~~bash
cd terraform/bootstrap-state
terraform init
terraform plan
terraform apply
~~~

Do not use the bootstrap configuration as the working directory for application deploy/destroy commands. Keep the S3 state bucket, the bootstrap configuration, and its local state.

## Repository layout

~~~text
.
├── .github/
│   └── workflows/
│       ├── terraform-validate.yml
│       └── terraform-deploy.yml
└── terraform/
    ├── bootstrap-state/    # One-time remote-state bucket resources
    ├── capacity.tf         # ASG and ECS capacity provider
    ├── compute.tf          # ECS-optimized AMI and EC2 launch template
    ├── ecs.tf              # ECS cluster and Container Insights
    ├── iam.tf              # EC2 and task-execution roles
    ├── loadbalancer.tf     # ALB, target group and HTTP listener
    ├── network.tf          # VPC, subnets, IGW and routes
    ├── providers.tf        # Region/account guard/default tags
    ├── security.tf         # ALB and ECS security groups/rules
    ├── service.tf          # ECS service
    ├── task.tf             # Task definition and CloudWatch logs
    └── versions.tf         # Terraform/provider constraints and S3 backend
~~~

## Technologies

AWS ECS on EC2, EC2 Auto Scaling, ECS capacity providers, VPC, subnets, Internet Gateway, Application Load Balancer, IAM, Systems Manager, CloudWatch Logs / Container Insights, S3 remote Terraform state, Terraform, GitHub Actions, and (planned) GitHub OIDC, SNS alerts, CloudWatch alarms, and S3 application backups.
