# Uptime Kuma on AWS ECS (EC2) with Terraform

This is a portfolio project for deploying [Uptime Kuma](https://github.com/louislam/uptime-kuma) on Amazon ECS using EC2 capacity, an Application Load Balancer (ALB), and Terraform.

> **Current state (16 October 2026):** The application stack is currently deployed for a temporary validation session. Uptime Kuma is reachable through the ALB, the target group is healthy, and an Auto Scaling replacement EC2 instance restored the previous application data from S3. Destroy the application stack after testing to control costs; retain the separate state and backup buckets.
>
> **Status of newer work:** GitHub Actions OIDC plan/apply has been exercised. The separate versioned S3 backup bucket is configured; a manual SSM backup uploaded an archive and checksum sidecar. After the EC2 instance was replaced, the restore-on-boot routine restored prior application data, ECS recovered, and the ALB target became healthy. The restore has been demonstrated end-to-end, but exact instance IDs, S3 object version/hash evidence, and measured RPO/RTO were not captured. CloudWatch/SNS alert delivery and each alarm condition still need verification. See [the restore drill](docs/restore-drill.md) and [OIDC setup](docs/oidc-setup.md).

## Goals

- Learn ECS scheduling, EC2 capacity, and Auto Scaling by using **ECS on EC2**, not Fargate.
- Provision infrastructure with Terraform and S3 remote state with native S3 lock files.
- Use an ALB, security groups, scoped IAM roles, Systems Manager, and CloudWatch.
- Keep costs controlled by deploying only for a test session, then destroying the application stack.
- Extend the project with OIDC-based GitHub Actions, actionable alarms, and an application backup that has been restored and verified.

## Architecture

The diagram shows the current test deployment and the recovery and alarm resources described in Terraform. The app is temporarily running for validation and should be destroyed after testing to control costs.

~~~mermaid
flowchart TB
  User((Browser))
  Internet((Internet))
  GH["GitHub repository<br/>Terraform + Actions"]
  OIDC["GitHub Actions OIDC<br/>short-lived AWS credentials<br/>roles require setup"]
  State[("Terraform state bucket<br/>versioning + SSE-S3<br/>native .tflock")]

  subgraph AWS["AWS eu-west-1 — temporary test deployment"]
    subgraph VPC["VPC 10.20.0.0/16"]
      IGW["Internet Gateway<br/>public default route"]
      subgraph AZA["Public subnet eu-west-1a"]
        EC2["ECS-optimized AL2023<br/>EC2 t3.small"]
      end
      subgraph AZB["Public subnet eu-west-1b"]
        Spare["Second public subnet"]
      end
    end

    ALB["Application Load Balancer<br/>attached to both subnets<br/>HTTP :80"]
    TG["Instance target group<br/>HTTP health check /"]
    ECS["ECS cluster + capacity provider<br/>ASG capacity 0–1"]
    App["Uptime Kuma task<br/>container :3001<br/>bridge + dynamic host port"]
    Logs[("CloudWatch Logs<br/>7-day retention")]
    SSM["SSM State Manager<br/>daily backup + hourly freshness"]
    Backup[("Separate app-backup S3 bucket<br/>versioning + SSE-S3<br/>14-day current-object retention")]
    Alarms["CloudWatch alarms<br/>ALB / ECS / ASG / backup"]
    SNS["Optional SNS email topic"]

    ALB --> TG
    TG -->|"observed host port 32768"| App
    ECS --> EC2
    EC2 --> App
    App --> Logs
    EC2 --> SSM
    SSM -->|"SQLite-consistent archive<br/>+ SHA-256 sidecar"| Backup
    Backup -. "verified latest archive<br/>on instance replacement" .-> EC2
    Alarms --> SNS
    IGW --> Internet
  end

  User -->|"HTTP :80 (test only)"| ALB
  App -->|"monitor checks: HTTP / HTTPS"| Internet
  GH --> OIDC -->|"Terraform API calls"| AWS
  OIDC --> State
~~~

The ECS task definition declares container port **3001** and host port **0**. ECS selected host port **32768** during the test and registered that port with the ALB target group. The configured security-group range is TCP **32768–65535**, while the instance's verified ephemeral range was **32768–60999**.

**TLS status:** this temporary test uses the ALB-generated AWS DNS name over HTTP only, restricted to a configured trusted IPv4 /32. There is no HTTPS listener or certificate, and the unused public 443 security-group rule has been removed. Do not enter reusable credentials or sensitive information through this endpoint. Before real use, configure a domain, ACM certificate, HTTPS listener and HTTP-to-HTTPS redirect, or keep the admin interface private.

## Component breakdown

### Network

- VPC: `10.20.0.0/16`, DNS support and DNS hostnames enabled.
- Public subnet 1: `10.20.1.0/24`, `eu-west-1a`.
- Public subnet 2: `10.20.2.0/24`, `eu-west-1b`.
- Internet Gateway, public route table, and default route to the Internet Gateway.
- Internet-facing ALB in both public subnets.
- Temporary test endpoint: the ALB accepts TCP 80 only from the operator-configured public IPv4 /32 in GitHub Actions variable `ALB_ALLOWED_CLIENT_CIDR` (or the optional `allowed_client_ipv4_cidr` workflow-dispatch override), and forwards to the ECS instance security group on the dynamic host-port range. The ALB-generated DNS name is plain HTTP; do not submit reusable credentials or sensitive information. Update the allowlist when your public IP changes, and remove public access or destroy the app stack when the test is finished.
- ECS instance security group accepts application traffic only from the ALB security group. It does not allow SSH or direct public inbound application access.
- EC2 egress permits TCP 80 and 443 for monitored websites, image pulls and AWS API access.
- Systems Manager is the administration path, so no inbound SSH rule is needed.

Public subnets avoid NAT Gateway charges in this learning-oriented design. A future private-subnet design should be evaluated against NAT/VPC endpoint costs rather than assumed to be cheaper.

### Compute and orchestration

- ECS cluster: `uptimekuma-cluster`, Container Insights enabled.
- ECS service: `uptimekuma-service`, desired count 1 during the test.
- Capacity provider backed by an EC2 Auto Scaling Group with min 0 / max 1.
- EC2 launch template: recommended ECS-optimized Amazon Linux 2023 AMI obtained through an SSM public parameter; instance type `t3.small`.
- Task resources: 256 CPU units and 512 MiB memory.
- Task network mode: `bridge`; container port 3001 and dynamic host-port assignment.
- The task image is pinned to the upstream `louislam/uptime-kuma:2.5.6` release rather than a moving major-version tag. Verify upstream releases before future upgrades.
- Application data mount: container `/app/data` to host `/var/lib/uptimekuma`.

ECS on EC2 was chosen to learn both orchestration and the capacity layer, rather than outsource compute to Fargate.

### IAM and Systems Manager

- **EC2 instance role:** ECS container-agent permissions and `AmazonSSMManagedInstanceCore`.
- **ECS task execution role:** `AmazonECSTaskExecutionRolePolicy` for image pulls and CloudWatch log publishing.
- No application task role was required by Uptime Kuma itself.
- The new host-based backup jobs run through SSM, so the EC2 instance role receives a narrowly scoped inline policy for only `s3://REPLACE_WITH_APP_BACKUP_BUCKET/uptimekuma/*` and the custom metric namespace `UptimeKuma/Backup`.
- No SSH ingress is configured.

### Terraform state and persistent backup storage

**Main state backend**

- Bucket: `REPLACE_WITH_EXISTING_TFSTATE_BUCKET`.
- State key: `uptimekuma/terraform.tfstate`.
- Region: `eu-west-1`.
- Versioning, SSE-S3 encryption, Block Public Access and native S3 lock file (`use_lockfile = true`).
- `prevent_destroy = true` in the bootstrap bucket resource.

**Application backup bucket**

- Separate Terraform root: `terraform/backup-infra/`.
- Bucket name: `REPLACE_WITH_APP_BACKUP_BUCKET`.
- State key: `uptimekuma/backup-infra.tfstate` in the state bucket above.
- Versioning, SSE-S3, Block Public Access, deny-insecure-transport policy.
- Current backup objects expire after 14 days; noncurrent object versions expire after 30 days.
- The bucket has `prevent_destroy = true`.

Apply `terraform/backup-infra/` before the main application stack. It assumes the Terraform state bucket already exists. Do not run application teardown from `terraform/bootstrap-state/` or `terraform/backup-infra/`. The bootstrap config uses local state unless separately migrated; preserve its working directory and state file.

### Logging and monitoring

- CloudWatch log group: `/ecs/uptimekuma`, retention 7 days.
- `terraform/monitoring.tf` defines ALB unhealthy/no-healthy-target alarms, ECS running task count, CPU and memory alarms, ALB/target 5xx alarms, ASG in-service capacity, backup freshness, and backup failure alarms.
- The optional `alert_email` variable creates an SNS topic and email subscription. Set GitHub repository variable `ALERT_EMAIL` or local `TF_VAR_alert_email`; the address must confirm the SNS subscription.
- Alarm actions are empty when the alert email variable is unset. Terraform having an alarm resource does not prove its metric dimensions, thresholds, state changes, or email delivery have been tested.

AWS Budget notifications at 50/80/100 percent remain future work and are not yet managed by Terraform.

## Backup and restore design

**Restore demonstrated successfully on 16 October 2026.** The daily SSM backup was triggered manually and uploaded an archive plus its checksum sidecar to S3. The EC2 instance was then replaced by Auto Scaling; the replacement restored the previous Uptime Kuma data, the ECS task became healthy, and the dashboard was accessible. The startup script checks the archive's SHA-256 and SQLite integrity before starting ECS. Exact evidence such as object version IDs, captured verification output, instance IDs and measured RPO/RTO still needs to be recorded.

- Daily SSM State Manager job at **02:05 UTC**.
- Uses SQLite's online backup API to create a transactionally consistent database snapshot, then packages that snapshot with the remaining application data.
- Uploads a timestamped archive and SHA-256 sidecar into the separate S3 backup bucket.
- An hourly SSM job checks the last archive's S3 timestamp and publishes a `BackupFresh` custom metric.
- On a new EC2 instance, launch-template user data finds the newest archive, downloads it and its checksum, verifies SHA-256 and runs SQLite `PRAGMA integrity_check` before restoring the data directory and starting the ECS agent. If an existing archive cannot be downloaded or validated, the startup script fails rather than silently discarding that recovery point.
- The S3 lifecycle rule retains current objects for 14 days and noncurrent versions for 30 days.

The backup bucket and SSM associations are deployed. A manual backup and replacement-instance restore succeeded, with prior application data present. Follow [docs/restore-drill.md](docs/restore-drill.md) to complete the evidence record; do not claim measured RPO/RTO or an explicitly verified named canary monitor unless those checks were captured.

Initial recovery targets to measure, not claim: **RPO under 24 hours** and **RTO under 30 minutes**.

## CI/CD: GitHub Actions with OIDC

Two workflows are committed:

- `.github/workflows/terraform-validate.yml`: on pull requests and pushes to `main`, runs `terraform fmt -check` and `terraform validate` for `terraform/`, `terraform/bootstrap-state/` and `terraform/backup-infra/`. No AWS credential is requested.
- `.github/workflows/terraform-deploy.yml`: manual dispatch only, on `main`. It assumes a plan role through OIDC, creates a saved Terraform plan and a review text artifact retained for one day. The apply job runs only when the operator selects mode `deploy`, types `DEPLOY`, and passes the `aws-deploy` GitHub Environment gate. Plan/apply jobs check the allowed AWS account ID and use short-lived credentials; there are no static AWS keys in the workflow.

The workflows will not authenticate until the AWS IAM OIDC provider, trust roles and GitHub variables are configured. Use [docs/oidc-setup.md](docs/oidc-setup.md). Configure the Environment to restrict deployments to `main` and require reviewer approval where available. OIDC trust and the actual apply path are not yet end-to-end tested. There is no automatic destroy job.

## What was actually tested

### Original stack test
- ECS service reached steady state with one running task.
- ALB target health was `healthy`.
- ECS mapped container port 3001 to EC2 host port 32768.
- EC2 ephemeral port range reported `32768–60999`, covered by the configured security-group range.
- Systems Manager Run Command succeeded without SSH.
- CloudWatch task log configuration was present.
- Terraform destroy of the main application stack completed.

The original destroy required intervention because ECS capacity management kept an instance in service while the task drained.

### New recovery and delivery test (16 October 2026)
- GitHub Actions OIDC plan/apply workflow successfully deployed the updated application configuration after IAM permissions were corrected.
- The daily SSM backup association was manually triggered and uploaded an archive and checksum sidecar to the persistent S3 bucket.
- The EC2 instance was replaced by Auto Scaling.
- The replacement restored the previous Uptime Kuma data from S3; the ECS task became healthy and the dashboard was accessible.
- The restore startup path checks the archive SHA-256 and runs SQLite `PRAGMA integrity_check` before starting ECS. The restored application coming up with prior data indicates that this path completed successfully.

The restore is demonstrated end-to-end, but the exact EC2 IDs, S3 object version/hash, captured startup output, measured RPO/RTO, and explicit named-canary check were not recorded during the session. Alarm delivery, HTTPS, and end-to-end tests of each alarm remain unverified. Terraform validation and successful apply do not substitute for those tests.

## Roadmap

### Phase 1 — secure the baseline
- Pin Uptime Kuma to a specific supported image version or digest; the current `louislam/uptime-kuma:1` tag is moving.
- Add HTTPS with ACM and a domain, or remove unused port 443 ingress until TLS is available.
- Apply `terraform/backup-infra/` before the application root.
- Run preflight and post-deploy checks. Improve teardown behavior around ECS draining and capacity-provider scale-in.

**Exit criteria:** repeatable deployment, healthy ALB target, successful SSM access, predictable teardown, no leftover billable resources.

### Phase 2 — prove CI/CD identity
- Configure GitHub OIDC provider and separate plan/apply IAM roles with subject conditions scoped to this repo and branch/Environment.
- Set GitHub repository variable `AWS_TERRAFORM_PLAN_ROLE_ARN`, environment variable `AWS_TERRAFORM_APPLY_ROLE_ARN`, and optional `ALERT_EMAIL`.
- Protect the `aws-deploy` Environment.
- Execute a plan-only workflow and a deliberately gated test deployment.

**Exit criteria:** plan works without static keys; untrusted pull requests cannot obtain AWS credentials; apply is explicit, scoped and audited.

### Phase 3 — prove alarms and cost controls
- Deploy the existing CloudWatch alarm and SNS configuration.
- Confirm the email subscription and safely trigger test alarm conditions.
- Add AWS Budget notifications at 50%, 80% and 100%.
- Confirm alarms recover to OK after the test.

**Exit criteria:** observed end-to-end alert delivery and tested recovery, not just alarm resources in Terraform.

### Phase 4 — prove recoverability (restore demonstrated; evidence capture incomplete)
- **Completed:** manually ran the SSM backup, found the archive/checksum in S3, replaced the EC2 instance, and confirmed prior Uptime Kuma data was restored and the app became healthy.
- Record the archive/version ID, SHA-256, timestamps, SSM execution ID, old/new instance IDs, and sanitized startup/log evidence in [docs/restore-drill.md](docs/restore-drill.md).
- Measure RPO/RTO rather than claiming target values; explicitly verify a named canary monitor if using one as the acceptance check.

**Exit criteria:** the restore path has been demonstrated. Finish evidence capture and measurements before presenting quantitative recovery claims.

### Phase 5 — harden and present the project
- Add Terraform static analysis/security checks and pin all GitHub Actions to commit SHAs (already done for the current workflows).
- Document IAM decisions and cost trade-offs, including ECS on EC2 versus Fargate and public versus private subnets.
- Capture sanitized screenshots for the working application, health check, OIDC workflow, alarm notification and restore drill.
- Consider private subnets and VPC endpoints if the additional cost/complexity makes sense for the learning goals.

## Cost-conscious runbook

The ALB and EC2 instance incurred ongoing hourly charges while deployed. Public IPv4, EBS, and CloudWatch may also contribute. ECS capacity-provider scaling can launch EC2 even if ASG desired capacity initially starts at zero, because an ECS service with desired count 1 needs compute.

For a test session:

1. Inspect the full Terraform plan before applying.
2. Deploy the persistent backup bucket first, then deploy the app.
3. Verify service and target health, logs, SSM, alarms, and create a known-good backup.
4. Exercise the restore drill before teardown if recovery is the test objective.
5. Run `terraform plan -destroy` from the main `terraform/` directory and inspect the entire plan.
6. Destroy only the main application stack; do not destroy the state backend or backup bucket.
7. Verify the ALB, running EC2 instance, leftover EBS volumes, unused public IPs, target groups and application log group are gone.

S3 state and backup storage continue to cost money, although this should be small for a low-volume portfolio. Current backup objects are lifecycle-expired, but the persistent buckets are intentionally protected from routine Terraform destroy.

## Commands

Create the application-backup bucket once (the Terraform state bucket must already exist):

~~~bash
cd terraform/backup-infra
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
~~~

Deploy the main stack for a test:

~~~bash
cd ../
terraform init
terraform fmt -check -recursive
terraform validate
# Optional SNS email alarm actions
export TF_VAR_alert_email="you@example.com"
terraform plan
terraform apply
~~~

After testing, inspect all proposed deletions first:

~~~bash
terraform plan -destroy
terraform destroy
~~~

If preparing a new account, bootstrap the Terraform state bucket once:

~~~bash
cd terraform/bootstrap-state
terraform init
terraform plan
terraform apply
~~~

Never run application destroy commands from `terraform/bootstrap-state/` or `terraform/backup-infra/`. Keep the state bucket and backup bucket. The main stack's Terraform state is stored at `uptimekuma/terraform.tfstate`; backup infrastructure state is at `uptimekuma/backup-infra.tfstate`.

## Repository layout

~~~text
.
├── .github/workflows/
│   ├── terraform-validate.yml
│   └── terraform-deploy.yml
├── docs/
│   ├── oidc-setup.md
│   └── restore-drill.md
└── terraform/
    ├── bootstrap-state/     # State bucket bootstrap (local state)
    ├── backup-infra/        # Persistent app-backup bucket (separate state)
    ├── backup.tf            # Daily SSM backup + hourly freshness metric
    ├── capacity.tf          # ASG and ECS capacity provider
    ├── compute.tf           # Launch template + restore-on-boot
    ├── ecs.tf               # ECS cluster and Container Insights
    ├── iam.tf               # EC2 and ECS execution roles
    ├── loadbalancer.tf      # ALB, target group and HTTP listener
    ├── monitoring.tf        # CloudWatch alarms and optional SNS
    ├── network.tf           # VPC, subnets, IGW and routes
    ├── providers.tf         # Region/account guard and default tags
    ├── security.tf          # ALB and ECS security groups/rules
    ├── service.tf           # ECS service
    ├── task.tf              # Task definition and CloudWatch logs
    ├── variables.tf         # Optional alert email
    └── versions.tf          # Terraform/provider constraints and S3 backend
~~~

## Technologies

AWS ECS on EC2, EC2 Auto Scaling, ECS capacity providers, VPC, Application Load Balancer, IAM, Systems Manager, CloudWatch Logs and alarms, SNS, S3 state and backup storage, SQLite backup/restore, Terraform, GitHub Actions and OIDC.
