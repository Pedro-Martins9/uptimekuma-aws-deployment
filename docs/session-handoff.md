# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 21 October 2026  
**Repository:** https://github.com/Pedro-Martins9/uptimekuma-aws-deployment  
**Default branch:** `main`  
**Current visibility:** public (verified through GitHub repository metadata)  
**Current app status:** redeployed on 20 October 2026. Terraform workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) succeeded (47 added, 0 changed, 0 destroyed). The operator reported HTTPS and HTTP-to-HTTPS redirection working, ECS running one task, a healthy ALB target, and successful backup/freshness checks. On 21 October, the operator confirmed S3 backup tests and alarm email tests (including recovery notifications) are complete, and budgets are configured. The freshness metric fix is deployed and the alarm cleared. The ALB-to-ECS dynamic host-port path is operationally verified: container port 3001 mapped to host port 32768; security groups permit TCP 32768–65535; the previously observed kernel ephemeral range 32768–60999 is covered. The operator estimates cumulative project-run cost at approximately €0.20; this is not an independently audited Cost Explorer total. No additional live test is required solely to close out the portfolio.  
**Domain for HTTPS test:** `pedromartins9.me`; Terraform default hostname: `uptime.pedromartins9.me`. The main application root now references an existing ACM certificate only when it is `ISSUED` in `eu-west-1` and matches the hostname. DNS routing is external to this Terraform root; ACM request/validation is currently being done in the console.

Use this document as the restart point for a future ChatGPT session. The repository is **PUBLIC** and the application was redeployed through the gated workflow on 20 October 2026. The operator reports that the hostname is working and HTTP redirects to HTTPS. Do not start a second apply while the stack is active. Review the pending post-deployment checks and control ongoing spend; publication and basic HTTPS access do not mean all engineering follow-ups are finished.

## 1. Project goal and design

Portfolio project deploying Uptime Kuma on **Amazon ECS using EC2 capacity**, managed with Terraform. ECS on EC2 was a deliberate choice to learn the EC2 capacity/orchestration layer instead of using Fargate.

Key components in the tested architecture:

- VPC with two public subnets, an internet-facing Application Load Balancer and security groups.
- ECS cluster/service and task using EC2 capacity through an Auto Scaling Group and capacity provider.
- ECS bridge networking with container port 3001 and dynamic host-port assignment.
- Systems Manager for administration; no inbound SSH rule.
- CloudWatch logs, alarms and optional SNS email subscription.
- Separate Terraform roots for state-bucket bootstrap, the application, persistent app-backup storage, and persistent account-wide cost controls.
- Daily SQLite-consistent application backup to S3, SHA-256 sidecar, and restore-on-EC2-startup validation.
- GitHub Actions for Terraform validation, Gitleaks scanning, and a manually gated Terraform plan/apply workflow using AWS OIDC.

AWS region used: `eu-west-1`. The application, backup-infra and cost-controls roots use partial S3 backend configuration with separate preserved state keys. Configure the existing remote-state bucket name as GitHub Actions repository secret `TFSTATE_BUCKET`; the workflow passes it to `terraform init -reconfigure -backend-config`. For local operations, export `TFSTATE_BUCKET` with the actual bucket name in your shell, then pass it to `terraform init -reconfigure -backend-config="bucket=$TFSTATE_BUCKET"`. Do not hardcode or commit the bucket name. Provider account guards use `aws_account_id`; set `TF_VAR_aws_account_id` explicitly.

## 2. Current AWS state — deployed 20 October 2026

The prior application stack was destroyed after the recovery test to control costs, then redeployed successfully through workflow run #20. Current state:

- The post-destroy audit completed successfully.
- The state and app-backup S3 buckets still exist.
- Terraform reported 19 resources destroyed in the main application root.
- The main application stack is deployed; the operator reports that the hostname serves the application and HTTP redirects to HTTPS.
- The operator reports a successful manual backup. The freshness-check SSM execution printed `BackupFresh=1` with a recent S3 timestamp. The root cause was incorrect syntax in `put-metric-data --dimensions`; the source fix in [`2b4b95b`](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/commit/2b4b95b36c604cbb5cd2d56c798a23962365f0e5) corrected all three custom-metric publication calls in `terraform/backup.tf`. Gated Terraform deployment [run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374) completed its plan and apply jobs successfully. The operator confirms that `BackupFresh` datapoints are visible under `Project=uptimekuma` and the freshness alarm is no longer in ALARM. Verify the latest daily archive and matching checksum object separately; scheduled-backup and restore-chain verification remains open.

The retained buckets are deliberately managed separately from the main app root. Their actual names are account-specific and must stay out of public-facing docs. The GitHub tree uses placeholders. They can continue to incur S3 storage charges; the exact current cost has not been measured here. Do not destroy the state bucket while it is needed by either remote-state root. Do not run routine app teardown from `terraform/bootstrap-state/`, `terraform/backup-infra/` or `terraform/cost-controls/`.

The main backend configuration points to the state bucket and key `uptimekuma/terraform.tfstate`; the backup-infrastructure state key is `uptimekuma/backup-infra.tfstate`. The bootstrap root uses local state unless migrated separately.

## 3. Tests demonstrated

### Application deployment
- ECS service reached steady state with one running task.
- ALB target became healthy and the dashboard loaded.
- ECS dynamically mapped container port 3001 to host port 32768; the task was observed RUNNING.
- The ALB/ECS security-group rules allow TCP 32768–65535, and the application is reachable through the ALB. The previously observed EC2 kernel ephemeral range was 32768–60999, within the allowed range. **Status: verified operationally; no further port investigation is needed unless a connectivity issue appears.**
- SSM Run Command worked without SSH.

### Backup and restore drill — successful
- Manual SSM backup uploaded an archive and SHA-256 sidecar to the persistent S3 backup bucket.
- Archive key pattern: `uptimekuma/archives/<UTC timestamp>.tar.gz`.
- Checksum sidecar pattern: `uptimekuma/checksums/<UTC timestamp>.tar.gz.sha256`.
- Auto Scaling replaced the EC2 instance.
- Replacement startup logged that it restored data from a verified timestamped S3 archive.
- The previous monitor configuration and history returned; the user confirmed the dashboard was accessible and the ALB target healthy.
- The restore path checks SHA-256 and runs SQLite `PRAGMA integrity_check` before starting the ECS agent. Direct command output was not captured separately.
- Recorded observations: archive timestamp 16:46:44Z; old instance termination 16:48:24Z; restore log 16:48:42Z. A dashboard screenshot later bounded recovery by about 13m11s from replacement launch. This is an upper bound inferred from timestamps, **not** an exact RTO. Exact RPO/RTO were not measured.
- Exact S3 object version ID, SHA-256 digest string, SSM execution ID, and direct SQLite `ok` output were not recorded.
- The named `RESTORE-DRILL-CANARY` monitor was not created; existing monitor data was used as the restore marker.

Detailed evidence remains in [docs/restore-drill.md](restore-drill.md). Its publication copy now records the confirmed teardown audit, preserves recovery bounds without exact RTO claims, and generalizes machine-specific identifiers.

## 4. GitHub Actions and repository state

Repository file tree currently includes:
- `.github/workflows/terraform-validate.yml`
- `.github/workflows/gitleaks.yml`
- `.github/workflows/terraform-deploy.yml`
- `docs/oidc-setup.md`
- `docs/portfolio-readiness.md`
- `docs/restore-drill.md`
- `docs/evidence-capture.md`
- `LICENSE` — Apache License 2.0 for this project's original work.
- Terraform configuration and provider lock files.

### Workflows
- **Terraform validation:** GitHub Actions passed formatting and validation for all four roots (application, bootstrap-state, backup-infra, cost-controls).
- **Gitleaks:** `.github/workflows/gitleaks.yml` uses Gitleaks Action v3 pinned to a commit SHA and CLI version `8.30.0`; full-history checkout is enabled. User confirmed the full-history Gitleaks scan is clean. This is not proof that a secret was never exposed: rotate any credential suspected to have been committed.
- **Terraform deployment:** manual dispatch only, main-branch gate, plan role via OIDC, encrypted short-retention plan artifact, explicit `DEPLOY` confirmation, and protected `aws-deploy` environment for apply. The plan/apply path was exercised successfully during the test. No automatic destroy workflow exists.

Latest publication-readiness update: [commit `bd505d043bcaebfb8aaeb802468ceb93db968b6b`](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/commit/bd505d043bcaebfb8aaeb802468ceb93db968b6b). The authoritative checklist is [`docs/portfolio-readiness.md`](portfolio-readiness.md), which now states **PUBLISHED** and records Apache License 2.0.

**Security and history status (19 October 2026):** the current tracked tree uses placeholders for account-specific values. I inspected the diffs of all 138 commits reachable from `main` through GitHub's API for concrete 12-digit AWS account IDs and literal state/backup bucket names; none were found. GitHub's refs endpoint exposed only `refs/heads/main`, with no tag refs. The operator confirmed that `gitleaks detect` returned no findings. No further force-push/history rewrite was performed because this reachable-history audit found no targeted literals to remove. This does not erase copies in local clones or guarantee immediate removal of GitHub's unreachable-object caches. Keep old local clones private and do not restore removed identifiers. Do not leave the old 'history cleanup is a publication blocker' wording in future docs.

## 5. Final closeout status — 21 October 2026

**Decision: the project is complete as a portfolio release.** The application stack was deployed successfully, the prior EC2 replacement restore drill is documented, and the operator confirms the S3 backup path, alarm and recovery email notifications, and AWS budget alerts are working. The approximate combined project-run cost reported by the operator is €0.20. No AWS account query or independent Cost Explorer export was performed during this documentation closeout.

Evidence links:
- [Successful application deployment — run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090)
- [SNS/email alarm deployment — run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112)
- [Backup freshness fix deployed — run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374)
- [Terraform validation](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358)
- [Gitleaks on the current documentation closeout commit](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/workflows/gitleaks.yml)
- [Restore-drill record](restore-drill.md)
- [Final evidence pack and screenshot plan](final-evidence.md)

Remaining items are portfolio polish, not deployment blockers:
- [ ] Optionally capture the sanitized screenshots listed in [final-evidence.md](final-evidence.md). Use existing output and read-only console views; do not repeat successful backup or alarm tests just for screenshots.
- [ ] Optionally add GitHub repository topics. The repository description is already set; GitHub currently reports no topics.
- [ ] Decide whether to retain the live app for demonstration. If retained, keep budgets enabled and monitor recurring charges. If removed, use a reviewed teardown of only the application root and audit billable resources; preserve Terraform state and backup storage intentionally.

**Completion boundary:** do not claim exact measured RPO/RTO, a project-only cost, or independently verified current runtime health unless the relevant evidence supports that claim. The exact €0.20 amount is an operator estimate, and the documented live-service state was last reported on 20 October 2026.

## 6. Technical guardrails

- The operator reports HTTPS is live and HTTP redirects to HTTPS; capture the browser certificate and redirect evidence for the portfolio.
- Do not claim alarm notifications are proven end-to-end.
- Do not claim exact measured RPO or RTO.
- The application is live according to the operator; independently verify current ECS task and target health before recording those checks as verified.
- The state and backup buckets persist and may still incur cost.
- Never commit Terraform state, plan artifacts, `.tfvars`, credentials, or private keys.
- Before a future deployment, inspect the entire Terraform plan and verify public ALB ingress is limited to IPv4 TCP 80/443. Keep ECS dynamic host ports restricted to the ALB security group. The current dynamic host-port path was verified operationally on 20 October 2026; only revisit it if connectivity issues arise or the networking configuration changes.
- If Terraform is initialized, avoid running apply or destroy until the target AWS identity, backend and intended action are explicitly confirmed.

## 7. Quick prompt for the next ChatGPT session

> Final closeout state as of 21 October 2026: this project is complete as a portfolio release. The operator confirms S3 backups, alarm and recovery email notifications, and AWS budget alerts are working; reported combined test/deployment spend is approximately €0.20, not independently audited. Do not redeploy or repeat those tests solely for screenshots. Use [docs/final-evidence.md](final-evidence.md) for the small sanitized evidence pack. Current-head Gitleaks passed at [run #39597613731](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/workflows/gitleaks.yml); Terraform validation passed on the latest Terraform-code commit at [run #39472903358](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358). The app deployment and backup metric fix are recorded in runs #20 and #22. Dynamic host-port configuration is already operationally verified for the deployment. Optional final polish: capture screenshots, add repository topics, and decide whether to retain the live service or run a controlled application-root teardown. Preserve the separate state and backup storage, keep account-specific values out of public files, and do not claim exact RPO/RTO or an independently measured cost without evidence.
