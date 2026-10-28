# Uptime Kuma on AWS — Terraform, ECS, CI/CD and Recovery

I deployed [Uptime Kuma](https://github.com/louislam/uptime-kuma) on **Amazon ECS using EC2 capacity**, with infrastructure provisioned by Terraform and deployments authenticated through GitHub Actions OIDC.

> **Portfolio project completed.** I demonstrated recovery after an EC2 replacement, restoring existing monitor configuration and history from an S3 backup whose SHA-256 checksum and SQLite integrity are validated before the ECS agent starts. The dashboard was usable within approximately **13 minutes 11 seconds of replacement launch** in the recorded drill; this is an observed upper bound, not a formally measured RTO. The application was last reported live on 20 October 2026. **The live demo may be available on request**; it is not intended to be continuously hosted.

## Results

- **Infrastructure as code:** Terraform-managed VPC, security groups, Application Load Balancer, ECS cluster/service, EC2 Auto Scaling Group and capacity provider.
- **Recovery demonstrated:** SQLite-consistent application backup to S3, SHA-256 verification, database-integrity check, and restoration of previous monitor data after EC2 replacement.
- **Deployment security:** GitHub Actions OIDC with short-lived AWS credentials, separate plan/apply roles, explicit apply confirmation, a protected deployment environment, and an encrypted short-retention Terraform plan artifact.
- **Operations and alerts:** CloudWatch logs and alarms, SNS email notifications, Systems Manager administration without public SSH, and a backup-freshness custom metric.

## Architecture

```mermaid
flowchart TB
    Browser[Browser] --> ALB[Application Load Balancer<br/>HTTPS via ACM]
    ALB --> TG[Target group and health checks]
    TG --> ECS[ECS service<br/>Uptime Kuma task]
    ECS --> EC2[EC2 capacity<br/>Auto Scaling + capacity provider]
    EC2 --> Logs[CloudWatch Logs]
    EC2 --> SSM[Systems Manager]
    SSM --> Backup[(S3 application backups<br/>archive + SHA-256)]
    Backup -. restore on replacement .-> EC2
    Alarms[CloudWatch alarms] --> SNS[SNS email notifications]
    GitHub[GitHub Actions] --> OIDC[AWS OIDC roles]
    OIDC --> TF[Terraform]
    TF --> State[(S3 remote state)]
```

## What I verified

The items below summarize the recorded tests and closeout checks. They do not imply that the live application was re-probed during this documentation update.

### Recovery after instance replacement

1. A Systems Manager backup job created a SQLite-consistent snapshot and uploaded a timestamped archive and SHA-256 sidecar to S3.
2. Auto Scaling replaced the EC2 instance.
3. Startup validated the archive checksum and SQLite database integrity before starting the ECS agent.
4. Uptime Kuma returned with its previous monitor configuration and history, and the application target became healthy.

The recorded drill bounds dashboard recovery to about 13 minutes 11 seconds after replacement launch. The initial drill did not capture a precise termination-request-to-healthy-target duration, exact RPO/RTO, the S3 object version ID, the digest string, or direct SQLite integrity output. I therefore describe recovery as demonstrated, not as a measured service-level objective.

[Read the restore-drill record](docs/restore-drill.md).

### Deployment and infrastructure checks

- [Application deployment — workflow run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090)
- [SNS/email alarm wiring — workflow run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112)
- [Backup-freshness metric fix — workflow run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374)
- [Terraform formatting and validation](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358)
- [Gitleaks secret-scanning workflow](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/workflows/gitleaks.yml)

I also operationally verified the ECS dynamic host-port path on 20 October 2026: container port 3001 mapped to host port 32768, and the security-group rules allowed TCP 32768–65535. The observed kernel ephemeral range was 32768–60999, within the permitted range.

I confirmed that S3 backup tests and alarm/recovery email tests were working, and that the backup-freshness metric fix was deployed. These checks were confirmed during project closeout; they were not independently re-run as part of this README update.

## Key design decisions

- **ECS on EC2, not Fargate:** I wanted to learn capacity management alongside container orchestration. The trade-off is additional responsibility for the EC2 launch template, ECS agent, capacity provider and Auto Scaling.
- **One active task with local SQLite data:** I avoided multiple tasks maintaining independent local databases. A production-scale design would need a deliberately chosen persistence and availability model rather than simply increasing the desired count.
- **S3 recovery with integrity gates:** backups are useful only if they can be restored. Startup verifies the archive checksum and database integrity before allowing ECS to start.
- **Systems Manager instead of SSH:** instance administration and backup operations use AWS Systems Manager, without an inbound SSH rule.
- **OIDC instead of long-lived AWS keys:** GitHub Actions assumes AWS roles using short-lived credentials. The deployment workflow separates planning from a gated apply.

## Security and operating model

The ALB is designed to accept public IPv4 HTTP/HTTPS traffic; HTTP redirects to HTTPS using an ACM certificate in `eu-west-1`. ECS host ports are restricted to traffic from the ALB security group. Since the Uptime Kuma login page is internet-accessible while the demo is running, I use a strong, unique admin password and enable Uptime Kuma two-factor authentication before exposing the dashboard publicly.

The app was intended to be time-boxed to control cost. The hostname may be offline when the demo is not running; contact me to arrange a live walkthrough. The Terraform state and application-backup S3 buckets are managed separately from the application stack and can continue to incur storage charges.

I have not attached an independently audited Cost Explorer export, so I am **not publishing a project cost total**. A configured budget threshold is a notification setting, not proof that that amount was spent.

## Repository structure

```text
.github/workflows/
  gitleaks.yml
  terraform-deploy.yml
  terraform-validate.yml
docs/
  evidence-capture.md
  final-evidence.md
  oidc-setup.md
  portfolio-readiness.md
  restore-drill.md
terraform/
  bootstrap-state/  # One-time state-bucket bootstrap
  backup-infra/     # Persistent application-backup storage
  cost-controls/    # Optional persistent AWS budget alerts
  *.tf              # Main application infrastructure
```

## Run it locally in your own AWS account

This project uses separate Terraform roots so persistent state and backups are not accidentally removed when the application is torn down. It is not a one-command deployment: you need AWS credentials, a remote-state bucket, the application-backup bucket, and an issued ACM certificate.

### Prerequisites

- Terraform `>= 1.12.0, < 2.0.0` (CI currently pins `1.16.5`).
- AWS CLI configured for the account you intend to use, with permission to manage the project resources. The provider region is `eu-west-1`.
- A DNS hostname you control and an ACM certificate in `eu-west-1` with status `ISSUED` covering that hostname. DNS records and certificate validation are managed outside Terraform.
- A state bucket named `uptimekuma-tfstate-<AWS_ACCOUNT_ID>` (or the exact existing bucket configured for your deployment), plus the application-backup bucket created by the `backup-infra` root.

Check the AWS identity before running Terraform. Do not continue if it is the wrong account. After copying the example file, edit `terraform/terraform.tfvars` and replace every placeholder with your actual account ID, hostname, and issued ACM certificate ARN. That file is ignored by Git and keeps the same inputs available for later plan, apply, and destroy commands.

### Windows PowerShell

```powershell
$accountId = (aws sts get-caller-identity --query Account --output text).Trim()
$env:TF_VAR_aws_account_id = $accountId
$stateBucket = "uptimekuma-tfstate-$accountId"
Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### Bash (Linux, macOS or Git Bash)

```bash
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TF_VAR_aws_account_id="$ACCOUNT_ID"
STATE_BUCKET="uptimekuma-tfstate-${ACCOUNT_ID}"
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

### 1. Bootstrap the state bucket (new accounts only)

Skip this step if the state bucket already exists. Do not run the bootstrap root against an existing bucket with an empty local state; it would try to create resources that already exist.

The bootstrap root uses local state because it creates the bucket that the other roots need. Run it once and preserve the local state file securely; it is ignored by Git. Review the plan before confirming the apply.

```powershell
terraform -chdir=terraform/bootstrap-state init
terraform -chdir=terraform/bootstrap-state plan
terraform -chdir=terraform/bootstrap-state apply
```

The bucket has `prevent_destroy` enabled and is intended to persist.

### 2. Configure the hostname and certificate

The default hostname is `uptime.pedromartins9.me`. Set `domain_name` in `terraform/terraform.tfvars` to the hostname you intend to serve.

Set `acm_certificate_arn` in the same file to the full ARN of the already-issued ACM certificate in `eu-west-1`. The certificate must be in the configured AWS account and cover the hostname in `domain_name`. The application root now uses this ARN directly rather than querying ACM by domain; this avoids a data-source lookup failure blocking a destroy when the certificate lookup cannot find a result.

Keep these values in `terraform/terraform.tfvars` instead of setting conflicting `TF_VAR_domain_name` environment variables. Terraform variable files take precedence over `TF_VAR_*` environment variables.

Complete ACM DNS validation and confirm the certificate is `ISSUED` in `eu-west-1` before continuing. Terraform does not create the DNS record or certificate in this project.

### 3. Create the persistent application-backup bucket

The following commands assume the state bucket created by the bootstrap root, or an equivalent existing bucket. Review the plan before confirming the apply.

```powershell
terraform -chdir=terraform/backup-infra init "-backend-config=bucket=$stateBucket"
terraform -chdir=terraform/backup-infra plan
terraform -chdir=terraform/backup-infra apply
```

Equivalent Bash commands:

```bash
terraform -chdir=terraform/backup-infra init -backend-config="bucket=${STATE_BUCKET}"
terraform -chdir=terraform/backup-infra plan
terraform -chdir=terraform/backup-infra apply
```

Do not skip this root for a fresh deployment: EC2 startup expects the backup bucket to exist, even when it contains no archives yet. The backup bucket is deliberately protected from accidental destruction.

### 4. Plan and deploy the application

```powershell
terraform -chdir=terraform init "-backend-config=bucket=$stateBucket"
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

Equivalent Bash commands:

```bash
terraform -chdir=terraform init -backend-config="bucket=${STATE_BUCKET}"
terraform -chdir=terraform plan
terraform -chdir=terraform apply
```

Review the plan before confirming the apply. You can optionally set `TF_VAR_alert_email` to receive CloudWatch alarm notifications; confirm the SNS email subscription after deployment. The domain's DNS record must point to the ALB after deployment.

For the optional account-wide budget, initialize and apply `terraform/cost-controls` as a separate root using the same backend bucket. Set `TF_VAR_budget_alert_email` and optionally `TF_VAR_monthly_budget_limit_usd`.

### 5. Safely tear down the application

Only destroy the main application root for routine teardown. Keep the state bucket, backup infrastructure and cost-controls root separate so recovery data and account-wide safeguards can remain.

```powershell
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform show destroy.tfplan
terraform -chdir=terraform apply destroy.tfplan
```

Read the entire destroy plan before applying it. The plan file is ignored by Git. When the destroy completes, verify the remaining AWS resources and review possible charges from persistent S3 buckets. Do not destroy `terraform/bootstrap-state` or `terraform/backup-infra` as part of routine application teardown.

## Further reading

- [OIDC setup and GitHub Actions permissions](docs/oidc-setup.md)
- [Backup and restore drill](docs/restore-drill.md)
- [Final evidence pack](docs/final-evidence.md)
- [Evidence capture guide](docs/evidence-capture.md)
- [Portfolio readiness and closeout notes](docs/portfolio-readiness.md)

## Technologies

AWS ECS on EC2, EC2 Auto Scaling, VPC, Application Load Balancer, ACM, IAM, Systems Manager, CloudWatch, SNS, S3, SQLite, Terraform, GitHub Actions, OIDC and Gitleaks.

## License

This project is licensed under the [Apache License 2.0](LICENSE). The license applies to this project's original work; third-party tools and dependencies remain subject to their own licenses.
