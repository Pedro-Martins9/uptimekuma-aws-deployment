# Uptime Kuma on AWS with Terraform

A cloud/DevOps portfolio project that deploys [Uptime Kuma](https://github.com/louislam/uptime-kuma) on **Amazon ECS using EC2 capacity**. It combines infrastructure as code, networking, container orchestration, monitoring, secure administration, automated backups, recovery testing and GitHub Actions with AWS OIDC.

> **Current status: deployed.** Terraform deployment workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) completed on 20 October 2026 with 47 resources added, 0 changed and 0 destroyed. The operator reports that `https://uptime.pedromartins9.me` serves the application and HTTP redirects to HTTPS. ECS has one running task, the ALB target is healthy on port 3001, and manual backup plus freshness-check runs succeeded. Remaining checks are dynamic port-range verification, the backup-freshness alarm state, and SNS email notification setup/testing. The separate Terraform-state and application-backup S3 buckets remain intentionally and may incur storage charges.

## At a glance

| Area | What this project demonstrates |
|---|---|
| Infrastructure as code | Terraform-managed VPC, security groups, ALB, ECS, EC2 Auto Scaling, IAM and CloudWatch |
| Container orchestration | ECS on EC2 with a capacity provider and dynamic host-port mapping |
| Secure administration | Systems Manager instead of public SSH access |
| Recovery | SQLite-consistent backup, S3 storage, SHA-256 verification and integrity-checked restore |
| CI/CD identity | GitHub Actions using short-lived AWS credentials through OIDC, with separate plan and gated apply roles |
| Cost control | Time-boxed test deployments, documented teardown and separate persistent storage |
| Repository checks | Terraform formatting/validation workflow and Gitleaks secret scanning |

## Architecture

This architecture was redeployed on 20 October 2026. The operator reports the public hostname is working and HTTP redirects to HTTPS; remaining operational checks are tracked in [portfolio readiness](docs/portfolio-readiness.md).

~~~mermaid
flowchart TB
    Browser[Browser] --> ALB[Application Load Balancer]
    ALB --> TG[Target group and health checks]
    TG --> Service[ECS service and Uptime Kuma task]
    Service --> EC2[EC2 capacity managed by Auto Scaling]
    EC2 --> Logs[CloudWatch Logs]
    EC2 --> SSM[Systems Manager backup jobs]
    SSM --> Backup[(S3 application backups)]
    Backup -. verified archive on replacement .-> EC2

    Alarms[CloudWatch alarms] --> SNS[Optional SNS email notifications]

    GitHub[GitHub Actions] --> OIDC[AWS OIDC roles]
    OIDC --> TF[Terraform-managed infrastructure]
    TF --> State[(S3 Terraform state)]
~~~

## What I built and tested

### ECS on EC2

I chose ECS on EC2 rather than Fargate to learn both the orchestration layer and the capacity underneath it. Terraform provisions the network, load balancer, ECS cluster and service, EC2 launch template, Auto Scaling Group, capacity provider, IAM roles and security groups.

The service reached steady state during testing and the load balancer target became healthy. The EC2 instances were administered through Systems Manager; no inbound SSH rule was required.

### Backup and recovery

The recovery path was tested end to end:

1. A manual Systems Manager backup job created a transactionally consistent SQLite snapshot and uploaded a timestamped archive plus SHA-256 checksum sidecar to S3.
2. Auto Scaling replaced the EC2 instance.
3. The replacement verified the archive checksum and ran SQLite `PRAGMA integrity_check` before starting the ECS agent.
4. Uptime Kuma returned with its previous monitor configuration and history, and the application target became healthy.

This demonstrates that the saved application data could be restored after instance replacement. **Exact RPO and RTO measurements were not captured**, so the project does not claim a measured recovery objective.

### GitHub Actions and OIDC

The repository includes three workflows:

- **Terraform validation** — formatting and configuration validation for the application, bootstrap and backup-infrastructure roots.
- **Gitleaks** — secret scanning on pushes and pull requests, with scheduled and manual runs for broader history scanning.
- **Terraform deployment** — manual plan/apply workflow using OIDC, short-lived AWS credentials, an encrypted short-retention plan artifact, explicit deploy confirmation and a protected GitHub Environment.

The validation workflow has passed, and the full-history Gitleaks scan has been reviewed successfully. The deployment workflow was exercised during the project test. No static AWS access keys are embedded in the workflows.

## Design decisions

- **ECS on EC2 instead of Fargate:** this project was built to learn both container orchestration and the EC2 capacity layer. The trade-off is more responsibility for instance capacity, the ECS agent, launch templates and Auto Scaling.
- **SQLite with consistent S3 backups instead of a shared filesystem:** a SQLite-consistent snapshot, checksum sidecar and startup integrity check made recovery testable without introducing EFS or an external database. The design uses a single active application task and restore-on-boot; it is not a multi-writer database design.
- **One active ECS task:** this avoids multiple tasks maintaining independent local SQLite copies. At scale, I would first establish a persistence architecture supported by the application, then test multi-task behavior and availability zones rather than simply increasing desired count.
- **TLS termination at the ALB:** Terraform looks up an already-requested ACM certificate for `uptime.pedromartins9.me`, serves HTTPS on port 443, and redirects HTTP on port 80 to HTTPS with `HTTP_301`. The certificate must be in `eu-west-1`, have status `ISSUED`, and cover the configured hostname. The default certificate lookup matches ACM's primary domain name exactly. If the issued certificate uses a different primary domain (for example, the apex or a wildcard) but its certificate names still cover `uptime.pedromartins9.me`, set the GitHub Actions variable `ACM_CERTIFICATE_LOOKUP_DOMAIN` to that exact primary domain; locally use `TF_VAR_acm_certificate_lookup_domain`. The ALB is intended to be internet-accessible over IPv4 TCP 80/443; ECS instance ingress remains limited to dynamic host-port traffic from the ALB security group. DNS records remain managed outside this Terraform root. Terraform deployment run #20 completed successfully on 20 October 2026. The operator reports that the hostname is routed to the application and HTTP redirects to HTTPS. This confirms the initial deployment and reported redirect, not end-to-end alarm delivery, backup success, or the new instance's ephemeral-port configuration.
- **Terraform state locking:** the remote S3 backends use native S3 lock files (`use_lockfile = true`) and per-root state keys; the state bucket uses versioning. The bootstrap root still uses local state unless deliberately migrated.

## Backup schedule and recovery objective

The SSM backup is scheduled daily at **02:05 UTC**. A separate hourly check publishes whether the most recent archive is no more than 26 hours old. The nominal backup interval is about 24 hours, but this is not a guaranteed RPO: the actual recoverable point depends on the age of the latest successful, integrity-checked backup when an incident occurs. Failed or skipped jobs can make the data-loss window longer.

The previous restore drill demonstrated that the app's existing data returned after EC2 replacement. Available timestamps bounded dashboard recovery to about **13 minutes 11 seconds after replacement launch**, but did not record termination-request-to-healthy-target time exactly. Treat that as an observed upper bound from screenshots, not a measured RTO. A future drill should record the termination request and first healthy target timestamps directly.

## Evidence and CI

- [Terraform formatting and validation — successful run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39039712681)
- [Gitleaks secret scanning — successful run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39040173879)

The repository includes the workflows and restore-drill record, and the application has been redeployed at `uptime.pedromartins9.me`. No short demo video is available. Total project cost has not yet been extracted from Cost Explorer, so no cost figure is claimed.

## Security and known limitations

- **Public HTTPS exposure:** deployment run #20 created the ALB HTTPS listener and HTTP-to-HTTPS redirect, and the operator reports that `uptime.pedromartins9.me` is live with HTTP redirecting to HTTPS. The certificate is looked up in `eu-west-1`; the selected certificate must cover the service hostname. If the certificate's primary domain differs, `ACM_CERTIFICATE_LOOKUP_DOMAIN` must match that exact primary domain, while the certificate's names/SANs must still cover `uptime.pedromartins9.me`. A certificate for apex `pedromartins9.me` alone does not cover the subdomain. Because the login page is internet-accessible, use a strong, unique admin password and keep ECS dynamic host ports private behind the ALB security group. Verify target health and the current EC2 instance's ephemeral-port range as recorded in [portfolio readiness](docs/portfolio-readiness.md).
- CloudWatch alarm resources are defined, but end-to-end SNS delivery and every alarm condition have not been demonstrated.
- A separate `terraform/cost-controls/` root defines an account-wide monthly USD budget with actual-spend notifications at 50%, 80% and 100%, excluding credit offsets. It is not enabled until `BUDGET_ALERT_EMAIL` is configured, and email delivery has not yet been tested.
- Exact S3 object-version/checksum evidence and precise RPO/RTO measurements were not captured during the recovery drill.
- Persistent S3 state and backup storage remain after application teardown. They are intentionally managed separately from the application stack and may continue to incur storage charges.

## Repository layout

~~~text
.
├── LICENSE
├── .github/workflows/
│   ├── gitleaks.yml
│   ├── terraform-deploy.yml
│   └── terraform-validate.yml
├── docs/
│   ├── oidc-setup.md
│   ├── portfolio-readiness.md
│   └── restore-drill.md
└── terraform/
    ├── bootstrap-state/   # One-time state-bucket bootstrap
    ├── backup-infra/      # Persistent backup bucket, separate root
    ├── certificate.tf     # Look up the issued ACM certificate for the domain
    ├── backup.tf          # Scheduled backup and freshness checks
    ├── outputs.tf         # ALB DNS name and zone ID for external DNS
    ├── capacity.tf        # Auto Scaling and ECS capacity provider
    ├── compute.tf         # Launch template and restore-on-boot
    ├── ecs.tf
    ├── iam.tf
    ├── loadbalancer.tf
    ├── monitoring.tf
    ├── network.tf
    ├── providers.tf
    ├── security.tf
    ├── service.tf
    ├── task.tf
    ├── variables.tf
    └── versions.tf
~~~

## Trying it yourself

This repository is a learning project, not a one-click deployment. Before deploying it in your own AWS account:

1. Install Terraform and AWS CLI, and configure an AWS identity with the permissions required by the chosen workflow.
2. Review the [OIDC setup guide](docs/oidc-setup.md) if using GitHub Actions. Replace every placeholder and configure the repository variables/secrets described there.
3. In GitHub repository **Settings → Secrets and variables → Actions → Secrets**, set `TFSTATE_BUCKET` to the name of the existing Terraform state S3 bucket. The backend blocks intentionally leave `bucket = ""`; the deployment workflow passes the secret to `terraform init` and fails early if it is missing. For local runs, set `TFSTATE_BUCKET` in your shell and pass it through `-backend-config="bucket=$TFSTATE_BUCKET"` rather than editing or committing the bucket name. Also set `TF_VAR_aws_account_id` to the expected 12-digit AWS account ID; do not commit account-specific values.
4. Bootstrap or reuse the existing Terraform state bucket; configure and apply `terraform/cost-controls/` if you want persistent account-wide budget alerts; then apply `terraform/backup-infra/`, and finally plan the main application root in `terraform/`.
5. Review the **entire** Terraform plan before applying. The default hostname is `uptime.pedromartins9.me` (override with `TF_VAR_domain_name` or the GitHub Actions repository variable `UPTIME_KUMA_DOMAIN_NAME`). The ACM certificate must be `ISSUED` in `eu-west-1` and cover the hostname. By default its primary domain must be `uptime.pedromartins9.me`; use `ACM_CERTIFICATE_LOOKUP_DOMAIN` when the valid certificate has a different primary domain (such as the apex or a wildcard). The ALB is public on IPv4 ports 80/443; use strong Uptime Kuma credentials and keep ECS host ports accessible only from the ALB security group.

For recovery-test instructions, see [the restore drill](docs/restore-drill.md). For the remaining hardening and portfolio steps, see [portfolio readiness](docs/portfolio-readiness.md).

### Teardown and costs

The current application resources are deployed. When the agreed test window ends, review the destroy plan and destroy only the main application root if you intend to stop the stack. **Do not destroy the state-storage, backup-infrastructure or cost-controls roots as part of routine application teardown.** Check EC2, load balancing, EBS, CloudWatch and billing after teardown. The retained S3 buckets are separate and can continue to incur small charges.

## Technologies

AWS ECS on EC2, EC2 Auto Scaling, VPC, Application Load Balancer, IAM, Systems Manager, CloudWatch, SNS, S3, SQLite, Terraform, GitHub Actions, OIDC and Gitleaks.

## License

This project is licensed under the [Apache License 2.0](LICENSE). The license applies to this project's original work; third-party tools and dependencies remain subject to their own licenses.

## Further reading

- [OIDC setup and GitHub Actions permissions](docs/oidc-setup.md)
- [Backup and restore drill evidence](docs/restore-drill.md)
- [Evidence capture runbook](docs/evidence-capture.md)
- [Portfolio readiness and remaining improvements](docs/portfolio-readiness.md)
