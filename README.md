# Uptime Kuma on AWS with Terraform

A cloud/DevOps portfolio project that deploys [Uptime Kuma](https://github.com/louislam/uptime-kuma) on **Amazon ECS using EC2 capacity**. It combines infrastructure as code, networking, container orchestration, monitoring, secure administration, automated backups, recovery testing and GitHub Actions with AWS OIDC.

> **Current status: the application stack is offline.** I deployed and tested the stack, demonstrated recovery from an S3 backup, then destroyed the application resources to control costs. The teardown audit completed successfully. The separate Terraform-state and application-backup S3 buckets remain intentionally, so small storage charges may continue.

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

This is the architecture used during testing; it is **not currently running**.

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

## Security and known limitations

- The test load balancer used **HTTP only**, restricted to a configured client IPv4 address. HTTPS/TLS was not implemented, and the application is offline. Do not use this temporary configuration to host a public dashboard as-is.
- CloudWatch alarm resources are defined, but end-to-end SNS delivery and every alarm condition have not been demonstrated.
- AWS Budget notifications are not yet managed by Terraform.
- Exact S3 object-version/checksum evidence and precise RPO/RTO measurements were not captured during the recovery drill.
- Persistent S3 state and backup storage remain after application teardown. They are intentionally managed separately from the application stack and may continue to incur storage charges.

## Repository layout

~~~text
.
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
    ├── backup.tf          # Scheduled backup and freshness checks
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
2. Review the [OIDC setup guide](docs/oidc-setup.md) if using GitHub Actions. It contains account-specific example values that must be updated for another account.
3. Review the backend bucket, provider account guard, and other account-specific settings in the Terraform configuration before initializing the application root.
4. Bootstrap the Terraform state storage, then apply `terraform/backup-infra/`, and finally plan the main application root in `terraform/`.
5. Review the **entire** Terraform plan before applying. The application requires an allowed client IPv4 CIDR for the temporary HTTP endpoint; never leave an administrative dashboard exposed more broadly than intended.

For recovery-test instructions, see [the restore drill](docs/restore-drill.md). For the remaining hardening and portfolio steps, see [portfolio readiness](docs/portfolio-readiness.md).

### Teardown and costs

The application resources and compute were destroyed after testing. If you deploy a new test stack, inspect the destroy plan and destroy only the main application root after the test. **Do not destroy the state-storage or backup-infrastructure roots as part of routine application teardown.** Check EC2, load balancing, EBS, CloudWatch and billing after teardown. The retained S3 buckets are separate and can continue to incur small charges.

## Technologies

AWS ECS on EC2, EC2 Auto Scaling, VPC, Application Load Balancer, IAM, Systems Manager, CloudWatch, SNS, S3, SQLite, Terraform, GitHub Actions, OIDC and Gitleaks.

## Further reading

- [OIDC setup and GitHub Actions permissions](docs/oidc-setup.md)
- [Backup and restore drill evidence](docs/restore-drill.md)
- [Portfolio readiness and remaining improvements](docs/portfolio-readiness.md)
