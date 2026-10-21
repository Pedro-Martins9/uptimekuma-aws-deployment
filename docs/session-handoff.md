# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 20 October 2026  
**Repository:** https://github.com/Pedro-Martins9/uptimekuma-aws-deployment  
**Default branch:** `main`  
**Current visibility:** public (verified through GitHub repository metadata)  
**Current app status:** redeployed on 20 October 2026. Terraform workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) succeeded (47 added, 0 changed, 0 destroyed). The operator reports HTTPS works and HTTP redirects to HTTPS; ECS has one running Uptime Kuma task, the ALB target is healthy, and manual backup plus freshness-check runs succeeded. Backup freshness fix verified live: the operator confirms `BackupFresh` datapoints are visible with the intended dimensions and the freshness alarm has cleared. The ALB-to-ECS dynamic host-port path is operationally verified: the ECS task maps container port 3001 to host port 32768, the security-group rules permit TCP 32768–65535, and the previously observed kernel ephemeral range 32768–60999 falls within that range. Remaining full-audit items: recovery (`OK`) email and the latest S3 archive/checksum pair.  
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

## 5. Completion definition — final closeout

The project is already published; do not use "finished" to imply a permanently running production service. Close the remaining portfolio milestone after these steps:

1. Read-only inspect the newest timestamped S3 archive and its matching SHA-256 sidecar. Record sanitized output showing the pair matches. No extra restore drill is required to support the existing recovery claim unless you specifically want tighter recovery evidence.
2. In the isolated test window, verify the recovery (`OK`) email from a safe alarm transition and return the alarm to normal. Record the result.
3. Capture a small sanitized evidence set: successful deployment run, HTTPS/redirect and healthy target, prior restore success, latest archive/checksum pair, and alarm/recovery email.
4. Decide the cost-controls root explicitly: apply the account-wide budget after reviewing scope and recipient, or document that budget alerts are deferred. Review retained S3 bucket usage and current spend without publishing bucket names/account IDs.
5. Complete portfolio polish: verify public rendering and relative links while signed out, set the GitHub repository description, and add topics.
6. Make README, readiness checklist, and handoff wording consistent. Run validation and Gitleaks after these documentation updates.
7. After the agreed test window, use the documented controlled teardown, audit remaining billable resources, and retain state/backup buckets deliberately. This is a cost-control action, not a prerequisite to claim that the portfolio project was built and tested.

**Definition of done:** public documentation is internally consistent; current security/validation checks pass; recovery and backup claims have the evidence actually captured; notification test results are accurately scoped; costs and persistent storage are accounted for. Exact RPO/RTO or project-only cost claims are optional and must not be invented.

## 5. Prioritized next-session plan

The repository is public. Do not repeat completed history or teardown checks unless new commits, alerts, or evidence justify doing so.

### Priority 1 — finish post-publication housekeeping (no AWS spend)
- [x] Change repository visibility to public and verify the GitHub metadata reports `visibility: public`.
- [ ] Open the repository in a signed-out/private browser window and verify README, docs, workflow files, architecture diagram and relative links render correctly.
- [ ] Set a concise repository description. The GitHub repository metadata still has an empty description. Suggested: "Terraform-managed Uptime Kuma on ECS/EC2 with OIDC delivery, CloudWatch monitoring and S3 backup/restore."
- [ ] Add relevant topics: `aws`, `terraform`, `ecs`, `devops`, `github-actions`, `oidc`, `infrastructure-as-code`. GitHub metadata currently reports no topics.
- [x] Add Apache License 2.0 at the repository root and link it from the README. It covers the project's original work; third-party tools and dependencies remain subject to their own licenses.

### Priority 2 — verify cost protection and deployment identity before redeployment
- [ ] Read-only review the two retained S3 buckets, their purpose and ongoing storage use. Preserve the state bucket while either remote-state root depends on it; don't use application teardown to delete persistent storage.
- [ ] Decide whether to enable `terraform/cost-controls/`. It defines an account-wide monthly budget (default USD 10) with actual-spend notifications at 50%, 80% and 100%, excluding credits. Set the intended notification email, review the account-wide scope and apply it only after an approved plan. Budget notifications are not a hard spending cap.
- [ ] Before any workflow deployment, verify GitHub repository variables/secrets, `aws-deploy` environment protection/reviewers, AWS OIDC trust conditions, and plan/apply role permissions. These account settings have not been independently verified from the repository-file review.
- [ ] Keep the current stack deployed only for the agreed test window, monitor spend, and plan a controlled teardown when testing is finished.

### Priority 3 — post-deployment verification and evidence
- [x] **HTTPS and DNS:** workflow run #20 completed, and the operator reports that the domain serves the application with HTTP redirecting to HTTPS. Verify the browser certificate and current ALB target health. The ALB is public on IPv4 ports 80/443; ECS host ports should remain restricted to the ALB security group.
- [x] **SNS alarm-email path configured and partially tested:** deployment [run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112) created the SNS topic/subscription and updated ten alarms; the operator confirmed the email subscription and manually tested the CPU-high alarm, receiving an alert email. Remaining: verify the recovery (`OK`) email and, where useful, test email delivery for the now-recovered backup-freshness alarm.
- [ ] Repeat the restore drill with a canary monitor and collect the exact S3 version ID, checksum digest, SSM execution ID, direct SQLite integrity output, termination-request time and first healthy replacement-target time. Record dashboard usability separately; do not claim exact RPO/RTO until directly measured.
- [ ] Capture sanitized ECS, ALB, dashboard/restore, alarm-email, and GitHub Actions evidence.
- [ ] After Cost Explorer refreshes, report a cost only with its period, metric, attribution/filter, currency and gross-versus-credit-offset treatment. Include retained S3 costs and don't present account-wide costs as project-only costs.
- [ ] Improve and test the teardown procedure, which previously required reducing ASG desired capacity to zero and replanning. Audit the account after teardown and preserve the separate state/backup roots.

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

> Continue the Uptime Kuma AWS portfolio project from this handoff. The repository is public, and the application stack was redeployed successfully on 20 October 2026 through workflow run #20 (47 added, 0 changed, 0 destroyed). The operator reports that `uptime.pedromartins9.me` serves the application and HTTP redirects to HTTPS. Current checks reported by the operator: one ECS task running, ALB target healthy on port 3001, manual backup and freshness-check runs succeed, SNS subscription confirmed, and a controlled CPU-high alarm test generated an email. The `BackupFresh`/`BackupSuccess` metric-dimension fix (commit [`2b4b95b`](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/commit/2b4b95b36c604cbb5cd2d56c798a23962365f0e5)) is confirmed working live: datapoints are visible and the freshness alarm has cleared. Port-path verification is complete for the current deployment: ECS host port 32768 is within the configured 32768–65535 security-group range, and the previously observed kernel range 32768–60999 is covered. For the full audit, confirm the latest archive/checksum pair in S3 and the recovery email. Capture sanitized endpoint and infrastructure evidence, review cost alerts and Cost Explorer, then perform a controlled teardown when the test window ends. Keep ECS host ports private behind the ALB security group and account-specific IDs and bucket names out of public files.
