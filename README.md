# Uptime Kuma on AWS ECS (EC2) with Terraform

A cloud/DevOps portfolio project that provisions Uptime Kuma on **Amazon ECS using EC2 capacity**, with Terraform-managed networking, an Application Load Balancer, Auto Scaling, SSM-based administration, CloudWatch monitoring, S3-backed recovery, and a gated GitHub Actions workflow using OIDC.

> **Deployment status: offline.** The application stack was destroyed after deployment and recovery testing on 16 October 2026 to control costs. The persistent Terraform-state and application-backup buckets use separate Terraform roots and need a final post-destroy existence/cost check.

## Project at a glance

| Area | Implementation | Evidence / current status |
|---|---|---|
| Infrastructure as code | Terraform, separated state bootstrap, application and backup-storage roots | Main application stack was provisioned and later destroyed |
| Container platform | ECS on EC2, capacity provider, Auto Scaling Group, ECS-optimized Amazon Linux | ECS service reached steady state during testing |
| Networking | VPC, two public subnets, ALB, security-group-only app ingress, dynamic ECS host ports | ALB target was healthy; HTTP access was temporarily restricted to one client IPv4 /32 |
| Recovery | SQLite-consistent S3 backups, SHA-256 sidecar, checksum/database-integrity checks during instance startup | Replacement instance restored the existing `wewatch` monitor and history |
| Delivery | GitHub Actions, OIDC short-lived credentials, separate plan/apply roles, protected apply environment, encrypted one-day plan artifact | Plan/apply path was exercised; workflows do not use static AWS access keys |
| Observability | CloudWatch logs, service/ALB/ASG/backup alarms, optional SNS email | Alarm resources exist; end-to-end alarm delivery and each alarm condition still need testing |
| Cost control | Time-boxed deployment and Terraform teardown | Main destroy reported 19 resources destroyed; orphan and persistent-storage checks remain |

## Demonstrated outcomes

- Deployed Uptime Kuma as an ECS service on EC2 instead of Fargate to learn both orchestration and capacity management.
- Replaced an EC2 instance through Auto Scaling and observed recovery from an S3 backup, including the previous monitor and history returning.
- Used a checksum sidecar and SQLite integrity validation before starting ECS against restored data.
- Exercised a GitHub Actions OIDC plan/apply flow with short-lived AWS credentials, an explicit deploy confirmation, and an environment approval gate.
- Kept the administration path on Systems Manager Session Manager rather than opening SSH ingress.

**What this project does not claim yet:** HTTPS/TLS, proven SNS delivery, tested alarm thresholds/recovery, exact measured RPO/RTO, AWS Budget alerts, or a completed post-destroy billing/resource audit. The test endpoint used HTTP only and is not running now.

## Before making the repository public

Follow the ordered checklist in [Portfolio readiness](docs/portfolio-readiness.md). The highest-priority items are to scan the **full Git history** for secrets, verify post-destroy AWS resources and persistent buckets, and confirm the repository contains no state files, credentials, plans or private screenshots. The tracked file tree currently contains Terraform source and documentation rather than Terraform state, but the full history still needs a dedicated secret scan.

The configuration includes account-specific backend names, AWS account guards and OIDC trust examples. Do not run it in another account without updating those settings and reviewing the plan. For deployment workflow prerequisites, see [OIDC setup](docs/oidc-setup.md); for recovery evidence and limitations, see the [restore drill](docs/restore-drill.md).

---
## Goals

- Learn ECS scheduling, EC2 capacity, and Auto Scaling by using **ECS on EC2**, not Fargate.
- Provision infrastructure with Terraform and S3 remote state with native S3 lock files.
- Use an ALB, security groups, scoped IAM roles, Systems Manager, and CloudWatch.
- Keep costs controlled by deploying only for a test session, then destroying the application stack.
- Extend the project with OIDC-based GitHub Actions, actionable alarms, and an application backup that has been restored and verified.

## Architecture

The diagram shows the application architecture used for the deployment and restore test. The application resources have since been destroyed to control costs; the persistent state and backup buckets are managed separately.

~~~mermaid
flowchart TB
  User((Browser))
  Internet((Internet))
  GH["GitHub repository<br/>Terraform + Actions"]
  OIDC["GitHub Actions OIDC<br/>short-lived AWS credentials<br/>roles require setup"]
  State[("Terraform state bucket<br/>versioning + SSE-S3<br/>native .tflock")]

  subgraph AWS["AWS eu-west-1 — test stack now destroyed"]
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

**Restore demonstrated successfully on 16 October 2026.** Backup archive `uptimekuma/archives/20261016T164644Z.tar.gz` and its checksum sidecar were uploaded to S3. Auto Scaling replaced `i-0118b10e18ad8c2a0` with `i-02971a9f174fdf338`. The replacement journal recorded `Uptime Kuma data restored from verified backup: uptimekuma/archives/20261016T164644Z.tar.gz`; the existing `wewatch` monitor and history were present, ECS returned healthy, and the dashboard was accessible. The backup timestamp was 16:46:44Z, old-instance termination was 16:48:24Z, and restore success was logged at 16:48:42Z. The dashboard screenshot captured at 18:01:37 UTC+01 bounds recovery at no more than about 13 minutes 11 seconds after replacement launch; the precise first-healthy time wasn't captured. S3 object version ID, exact checksum digest, SSM execution ID, and direct SQLite integrity output still need to be recorded.

- Daily SSM State Manager job at **02:05 UTC**.
- Uses SQLite's online backup API to create a transactionally consistent database snapshot, then packages that snapshot with the remaining application data.
- Uploads a timestamped archive and SHA-256 sidecar into the separate S3 backup bucket.
- An hourly SSM job checks the last archive's S3 timestamp and publishes a `BackupFresh` custom metric.
- On a new EC2 instance, launch-template user data finds the newest archive, downloads it and its checksum, verifies SHA-256 and runs SQLite `PRAGMA integrity_check` before restoring the data directory and starting the ECS agent. If an existing archive cannot be downloaded or validated, the startup script fails rather than silently discarding that recovery point.
- The S3 lifecycle rule retains current objects for 14 days and noncurrent versions for 30 days.

The backup bucket remains managed by the separate `terraform/backup-infra/` root. The SSM associations were part of the main application stack and were removed during teardown. A manual backup and replacement-instance restore succeeded, with the prior `wewatch` monitor and history present. The observed timestamp-to-termination gap was about 1 minute 40 seconds, and the recovery-time upper bound is about 13 minutes 11 seconds from replacement launch; these are estimates based on recorded timestamps, not a precise snapshot-age or first-healthy measurement. The application resources were subsequently destroyed: Terraform reported 19 resources destroyed. See [docs/restore-drill.md](docs/restore-drill.md) for the evidence record and teardown notes.

Initial recovery targets to measure, not claim: **RPO under 24 hours** and **RTO under 30 minutes**.

## CI/CD: GitHub Actions with OIDC

Three workflows are committed:

- `.github/workflows/terraform-validate.yml`: on pull requests and pushes to `main`, runs `terraform fmt -check` and `terraform validate` for `terraform/`, `terraform/bootstrap-state/` and `terraform/backup-infra/`. No AWS credential is requested.
- `.github/workflows/gitleaks.yml`: runs the pinned Gitleaks Action v3 with the Gitleaks CLI pinned to `8.30.0` on pushes and pull requests to `main`, and on a daily schedule or manual dispatch. Checkout fetches the full Git history. Push and pull-request runs scan the relevant commit range; a manual or scheduled run performs the full-history scan needed before making this repository public. It uses a read-only token and does not need AWS credentials or a Gitleaks license for this personal-account repository. The initial full-history scan still needs to be run and reviewed before publication.
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
- Uptime Kuma is pinned to `louislam/uptime-kuma:2.5.6`; review upstream releases before future upgrades.
- Add HTTPS with ACM and a domain, or keep the HTTP endpoint restricted and temporary.
- The separate backup bucket is deployed and the replacement-instance restore has been demonstrated; finish recording the evidence and measured recovery times.
- Run preflight and post-deploy checks. Improve teardown behavior around ECS draining and capacity-provider scale-in.

**Exit criteria:** repeatable deployment, healthy ALB target, successful SSM access, predictable teardown, no leftover billable resources.

### Phase 2 — CI/CD identity (basic flow demonstrated)
- GitHub OIDC provider and separate plan/apply IAM roles are configured with repository and environment subject restrictions.
- The plan and gated apply workflows have run successfully using short-lived credentials; permissions were adjusted in response to AWS AccessDenied errors.
- Continue reviewing and tightening the apply role's permissions without breaking provider reads, resource lifecycle operations or launch-template use.
- Keep the `aws-deploy` Environment protected and retain the plan-review and approval steps.

**Exit criteria:** plan works without static keys; untrusted pull requests cannot obtain AWS credentials; apply is explicit, scoped and audited.

### Phase 3 — prove alarms and cost controls
- Deploy the existing CloudWatch alarm and SNS configuration.
- Confirm the email subscription and safely trigger test alarm conditions.
- Add AWS Budget notifications at 50%, 80% and 100%.
- Confirm alarms recover to OK after the test.

**Exit criteria:** observed end-to-end alert delivery and tested recovery, not just alarm resources in Terraform.

### Phase 4 — prove recoverability (restore demonstrated; evidence record partially complete)
- **Completed:** manually ran the SSM backup, captured the archive key and checksum sidecar, replaced the EC2 instance, found the restore-success log entry, and confirmed the existing `wewatch` monitor/history returned and the app became healthy.
- Remaining evidence to capture: S3 object version ID, exact checksum digest, SSM execution ID, and direct SQLite integrity output if required.
- Recorded observations: archive timestamp 16:46:44Z; old instance terminated at 16:48:24Z; restore success logged at 16:48:42Z; the healthy dashboard screenshot was captured at 18:01:37 UTC+01. This gives an approximate timestamp-to-termination gap of 1m40s and a recovery-time upper bound of 13m11s from replacement launch, not a precise RPO/RTO measurement.

**Exit criteria:** end-to-end restore demonstrated. Capture remaining evidence and label timing estimates appropriately before presenting recovery metrics.

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
