# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 19 October 2026  
**Repository:** https://github.com/Pedro-Martins9/uptimekuma-aws-deployment  
**Default branch:** `main`  
**Current visibility:** private; source is **ready to publish** according to `docs/portfolio-readiness.md`  
**Current app status:** application stack destroyed after successful deployment and restore testing; only separate Terraform state and application-backup S3 storage remain.

Use this document as the restart point for a future ChatGPT session. It records the current state and ordered next steps. The current repository decision is **READY TO PUBLISH** as an honest portfolio project; publication itself remains a manual GitHub visibility change. This is not a claim that every engineering enhancement is finished. Do not assume the app is running or deploy anything without reviewing the plan and confirming the intended spend.

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

AWS region used: `eu-west-1`. Remote state backends use `REPLACE_WITH_EXISTING_TFSTATE_BUCKET` placeholders and must be restored to the existing bucket name before running Terraform. Provider account guards use `aws_account_id`; set `TF_VAR_aws_account_id` explicitly.

## 2. Current AWS state — do not redeploy by assumption

The application stack was destroyed after the recovery test to control costs. The user confirmed:

- The post-destroy audit completed successfully.
- The state and app-backup S3 buckets still exist.
- Terraform reported 19 resources destroyed in the main application root.
- The main application stack is offline.
- The application-root SSM backup and freshness associations were removed with the main stack; scheduled backups do not run while it is offline.

The retained buckets are deliberately managed separately from the main app root. Their actual names are account-specific and must stay out of public-facing docs. The GitHub tree uses placeholders. They can continue to incur S3 storage charges; the exact current cost has not been measured here. Do not destroy the state bucket while it is needed by either remote-state root. Do not run routine app teardown from `terraform/bootstrap-state/`, `terraform/backup-infra/` or `terraform/cost-controls/`.

The main backend configuration points to the state bucket and key `uptimekuma/terraform.tfstate`; the backup-infrastructure state key is `uptimekuma/backup-infra.tfstate`. The bootstrap root uses local state unless migrated separately.

## 3. Tests demonstrated

### Application deployment
- ECS service reached steady state with one running task.
- ALB target became healthy and the dashboard loaded.
- ECS dynamically mapped container port 3001 to host port 32768.
- EC2 reported ephemeral range 32768–60999; the configured security-group range TCP 32768–65535 covered it.
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
- Terraform configuration and provider lock files.

### Workflows
- **Terraform validation:** GitHub Actions passed formatting and validation for all four roots (application, bootstrap-state, backup-infra, cost-controls).
- **Gitleaks:** `.github/workflows/gitleaks.yml` uses Gitleaks Action v3 pinned to a commit SHA and CLI version `8.30.0`; full-history checkout is enabled. User confirmed the full-history Gitleaks scan is clean. This is not proof that a secret was never exposed: rotate any credential suspected to have been committed.
- **Terraform deployment:** manual dispatch only, main-branch gate, plan role via OIDC, encrypted short-retention plan artifact, explicit `DEPLOY` confirmation, and protected `aws-deploy` environment for apply. The plan/apply path was exercised successfully during the test. No automatic destroy workflow exists.

Latest publication-readiness update: [commit `bd505d043bcaebfb8aaeb802468ceb93db968b6b`](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/commit/bd505d043bcaebfb8aaeb802468ceb93db968b6b). The authoritative checklist is [`docs/portfolio-readiness.md`](portfolio-readiness.md), which now states **READY TO PUBLISH**.

**Security and history status (19 October 2026):** the current tracked tree uses placeholders for account-specific values. I inspected the diffs of all 138 commits reachable from `main` through GitHub's API for concrete 12-digit AWS account IDs and literal state/backup bucket names; none were found. GitHub's refs endpoint exposed only `refs/heads/main`, with no tag refs. The operator confirmed that `gitleaks detect` returned no findings. No further force-push/history rewrite was performed because this reachable-history audit found no targeted literals to remove. This does not erase copies in local clones or guarantee immediate removal of GitHub's unreachable-object caches. Keep old local clones private and do not restore removed identifiers. Do not leave the old 'history cleanup is a publication blocker' wording in future docs.

## 5. Prioritized next-session plan

The publication security gate is marked PASS in `docs/portfolio-readiness.md`. Do not repeat completed history or teardown checks unless new commits or evidence justify doing so.

### Priority 1 — complete the manual publication steps
- [x] Sanitize the current tracked tree and audit the 138 commits reachable from `main`; no concrete AWS account ID or static state/backup bucket names were found in commit diffs.
- [x] Confirm the operator-reported full-history Gitleaks scan has no findings.
- [x] Update `docs/portfolio-readiness.md` to **READY TO PUBLISH**, distinguish publication blockers from follow-up engineering work, and retain an accurate offline/destroyed app status.
- [ ] Decide whether to add a `LICENSE`. There is no license file; do not imply reuse rights until the intended terms are chosen. This is a licensing decision, not a technical readiness failure.
- [ ] Set a concise repository description and useful topics in GitHub repository settings.
- [ ] Make the repository public manually in GitHub: **Settings → General → Danger Zone → Change repository visibility → Make public**. The connected GitHub tools can edit repository contents but cannot change visibility.
- [ ] After publication, inspect the repository in a signed-out/private browser window and verify that the README, docs and links render.

### Priority 2 — engineering and evidence follow-ups (not publication blockers)
- [ ] Cost controls: `terraform/cost-controls/` defines account-wide monthly budget alerts at 50%, 80% and 100% actual spend (default USD 10; credit offsets excluded). It is not applied or tested; do not claim active alerting.
- [ ] Alarm validation: verify SNS subscription and safely exercise meaningful CloudWatch alarm conditions including return to OK.
- [ ] Cost reporting: extract Cost Explorer data after refresh and state whether a reported figure is gross or credit-offset net. No project cost total is currently verified.
- [ ] Transport security: the test endpoint used HTTP restricted to a configured IPv4 `/32`; if redeploying for ongoing use, add domain/ACM/HTTPS and redirect, or keep the dashboard private.
- [ ] Next restore drill: capture exact S3 VersionId, checksum digest, SSM execution ID, direct SQLite integrity output, and precise request-to-healthy-target timestamps; optionally create a canary monitor.
- [ ] Improve and retest predictable ECS/ASG teardown, which initially required scaling ASG desired capacity to zero and replanning.
- [ ] Add sanitized screenshots/video after an approved, time-boxed deployment, following `docs/evidence-capture.md`. This is helpful portfolio evidence but not required to publish the current honest write-up.

## 6. Technical guardrails

- Do not claim HTTPS is implemented.
- Do not claim alarm notifications are proven end-to-end.
- Do not claim exact measured RPO or RTO.
- Do not claim the application is live; it was destroyed after the successful drill.
- The state and backup buckets persist and may still incur cost.
- Never commit Terraform state, plan artifacts, `.tfvars`, credentials, or private keys.
- Before a future deployment, inspect the entire Terraform plan and verify the allowed client IPv4 CIDR. The current test architecture used a public ALB with HTTP restricted to a configured IPv4 `/32`.
- If Terraform is initialized, avoid running apply or destroy until the target AWS identity, backend and intended action are explicitly confirmed.

## 7. Quick prompt for the next ChatGPT session

> Continue the Uptime Kuma AWS portfolio project from this handoff. The application stack is offline/destroyed and the separate Terraform state and app-backup buckets remain. `docs/portfolio-readiness.md` says **READY TO PUBLISH**: the current tree is sanitized, the operator reports a clean full-history Gitleaks scan, and GitHub's reachable-history audit covered all 138 commits with no literal AWS account ID or static state/backup bucket names found. Do not re-introduce a history-rewrite blocker without new evidence. Remaining publication actions are manual GitHub settings: description/topics, decide on a LICENSE, change visibility to public, then inspect while signed out. HTTPS, alarm delivery, precise RPO/RTO, evidence video and cost extraction remain follow-up work, not publication blockers. Do not deploy AWS resources without explicit approval of the test window and spend.
