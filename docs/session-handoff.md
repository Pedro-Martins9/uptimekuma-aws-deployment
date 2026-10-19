# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 17 October 2026  
**Repository:** https://github.com/Pedro-Martins9/uptimekuma-aws-deployment  
**Default branch:** `main`  
**Current visibility:** private  
**Current app status:** application infrastructure destroyed after testing; only the separate state and backup storage remain.

Use this document as the restart point for a future ChatGPT session. It records the current state and ordered next steps. Do not assume the app is running or deploy anything without reviewing the plan and confirming the intended spend.

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

The retained buckets are deliberately managed separately from the main app root. Their actual names are account-specific and remain in the private operational configuration; replace them with placeholders in public-facing docs unless the concrete values are intentionally disclosed. They can continue to incur small S3 storage charges. Do not destroy the state bucket while it is needed by either remote-state root. Do not run routine app teardown from `terraform/bootstrap-state/`, `terraform/backup-infra/` or `terraform/cost-controls/`.

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

Relevant recent commits:
- README simplified/sanitized: `3e38def95954b9161bf5d90a85ade195b2145a35`
- Readiness checklist updated after user confirmed cleanup/security results: `f0870e31727351d5cfc6e8f764048de2b7c98df1`
- Gitleaks scanner pin: `6ee16ce38ad1e8a16136b15eb4e887383303cdab`
- Gitleaks workflow created; the malformed `.github/workflows/main.yml` fragment was deleted.

The current tracked tree is sanitized; the cost-controls root and evidence-capture runbook are now present. The application stack remains offline and the cost budget is not applied. Remote backend bucket names are placeholders: restore the existing bucket name in each remote backend before Terraform init and set `TF_VAR_aws_account_id`. **Reachable-history audit completed 19 October 2026:** I checked all 138 commits reachable from `main` via GitHub's commit API and found no concrete 12-digit AWS account ID or literal state/backup bucket name in the commit diffs. GitHub's refs endpoint shows only `refs/heads/main`, with no tag refs. The operator also reports a clean `gitleaks detect` scan. No further rewrite was performed because the audit found no targeted literals. This does not erase copies in local clones or guarantee immediate removal of GitHub's unreachable-object caches; re-scan a local mirror before changing repository visibility.

## 5. Prioritized next-session plan

Work in this order. Do not re-run completed security scan or teardown checks unless changes justify re-running them.

### Priority 1 — history hygiene before publishing
- [x] Generalize `docs/oidc-setup.md` with placeholders while preserving the immutable subject-claim structure. Confirm the exact claim format against current GitHub documentation before configuring OIDC.
- [x] Update `docs/restore-drill.md` to reflect the confirmed teardown audit and persistent buckets; machine-specific identifiers and exact object keys are omitted from the publication copy.
- [x] Scan the current tracked files checked for literal account IDs, concrete state/backup bucket names and instance IDs; none remained in those files.
- [x] Audit all 138 commits reachable from `main` for concrete AWS account IDs and static state/backup bucket names; none were found in the commit diffs. GitHub currently exposes only `refs/heads/main` and no tag refs, and the operator reports a clean `gitleaks detect` scan. Re-scan a local mirror before changing repository visibility, as this audit cannot clear local clones or GitHub's unreachable-object caches. No forced history rewrite was performed because no targeted literals remained in reachable history. No commits were found for `terraform.tfvars` or `terraform/terraform.tfvars` on `main`; inspected `terraform/security.tf` history contained a prior wildcard CIDR and later the variable, not a personal literal `/32`.
- [x] Add design decisions, backup-frequency/RPO caveat, state-locking notes, CI run links, cost-controls Terraform and a recovery/evidence capture runbook.
- [ ] Confirm the budget configuration and notification delivery during the next approved test; do not claim the budget has been applied.

### Priority 2 — finish the public repository presentation
- [ ] Add a `LICENSE` only after choosing the intended reuse terms; no license file is currently tracked.
- [ ] Add sanitized screenshots/video after the next approved, time-boxed deployment, following `docs/evidence-capture.md`.
- [ ] Set a short GitHub repository description and useful topics through repository settings.
- [ ] Once satisfied, make the repository public manually in GitHub: **Settings → General → Danger Zone → Change repository visibility → Make public**. The connected GitHub file tools can update contents but have not exposed a visibility-change action.
- [ ] Check the public repository in a signed-out/private browser window.

### Priority 3 — engineering tasks (not blockers for documenting the completed test)
- [ ] Deploy temporarily if desired, configure HTTPS with a domain/ACM certificate or keep Uptime Kuma private, and test TLS/redirect behavior. The tested endpoint used HTTP only; the app is not running now.
- [ ] Verify SNS subscription and safely exercise CloudWatch alarm conditions including return to OK.
- [x] Implemented `terraform/cost-controls/` for account-wide monthly budget alerts at 50%, 80% and 100% actual spend (default USD 10; excludes credits). It is not deployed or tested.
- [ ] During the next restore drill, collect exact S3 VersionId, checksum digest, SSM execution ID, direct SQLite integrity output and precise timestamps; optionally create a named canary monitor.
- [ ] Improve and re-test predictable ECS/ASG teardown, which initially required scaling ASG desired capacity to zero and replanning.

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

> Continue the Uptime Kuma AWS portfolio project from this handoff. The application stack is offline. The current tracked tree is sanitized, Terraform validation and Gitleaks are green, and `terraform/cost-controls/` is implemented but not applied. First resolve the publication blocker: earlier Git commits contain the AWS account ID and concrete bucket names. Use an authenticated local clone and `git filter-repo` to rewrite the history, verify all refs and workflow logs, then scan the rewritten history. Keep the repository private until this is complete. Do not deploy AWS resources without explicit approval of the test window and spend.
