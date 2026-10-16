# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 16 October 2026  
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
- Separate Terraform roots for state-bucket bootstrap, the application, and persistent app-backup storage.
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

The retained buckets are deliberately managed separately from the main app root. Their actual names are account-specific and remain in the private operational configuration; replace them with placeholders in public-facing docs unless the concrete values are intentionally disclosed. They can continue to incur small S3 storage charges. Do not destroy the state bucket while it is needed by either remote-state root. Do not run routine app teardown from `terraform/bootstrap-state/` or `terraform/backup-infra/`.

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
- Terraform configuration and provider lock files.

### Workflows
- **Terraform validation:** user confirmed the workflow completed successfully for formatting and all three roots.
- **Gitleaks:** `.github/workflows/gitleaks.yml` uses Gitleaks Action v3 pinned to a commit SHA and CLI version `8.30.0`; full-history checkout is enabled. User confirmed the full-history Gitleaks scan is clean. This is not proof that a secret was never exposed: rotate any credential suspected to have been committed.
- **Terraform deployment:** manual dispatch only, main-branch gate, plan role via OIDC, encrypted short-retention plan artifact, explicit `DEPLOY` confirmation, and protected `aws-deploy` environment for apply. The plan/apply path was exercised successfully during the test. No automatic destroy workflow exists.

Relevant recent commits:
- README simplified/sanitized: `3e38def95954b9161bf5d90a85ade195b2145a35`
- Readiness checklist updated after user confirmed cleanup/security results: `f0870e31727351d5cfc6e8f764048de2b7c98df1`
- Gitleaks scanner pin: `6ee16ce38ad1e8a16136b15eb4e887383303cdab`
- Gitleaks workflow created; the malformed `.github/workflows/main.yml` fragment was deleted.

The OIDC guide, restore drill, readiness checklist, backend blocks and deploy workflow account guard are generalized. The repository remains private. Before Terraform use, restore the existing bucket name in both remote backend blocks and set `TF_VAR_aws_account_id`.

## 5. Prioritized next-session plan

Work in this order. Do not re-run completed security scan or teardown checks unless changes justify re-running them.

### Priority 1 — finish documentation sanitization before publishing
- [x] Generalize `docs/oidc-setup.md` with placeholders while preserving the immutable subject-claim structure. Confirm the exact claim format against current GitHub documentation before configuring OIDC.
- [x] Update `docs/restore-drill.md` to reflect the confirmed teardown audit and persistent buckets; machine-specific identifiers and exact object keys are omitted from the publication copy.
- [ ] Finish a full-tree publication review. Backend bucket references are placeholders and the AWS account guard is set at runtime; check Git history and all remaining Terraform/workflow values before changing visibility.
- [x] Inspect the edited docs for contradictions and stale teardown language; re-run a final full-tree review before publication.

### Priority 2 — finish the public repository presentation
- [ ] Add a `LICENSE` only after choosing the intended reuse terms; no license file is currently tracked.
- [ ] Optionally add sanitized screenshots of architecture, healthy target, approval-gated workflow and restore evidence. Do not include personal e-mail addresses, credentials, or unrelated monitor endpoints.
- [ ] Set a short GitHub repository description and useful topics through repository settings.
- [ ] Once satisfied, make the repository public manually in GitHub: **Settings → General → Danger Zone → Change repository visibility → Make public**. The connected GitHub file tools can update contents but have not exposed a visibility-change action.
- [ ] Check the public repository in a signed-out/private browser window.

### Priority 3 — engineering tasks (not blockers for documenting the completed test)
- [ ] Deploy temporarily if desired, configure HTTPS with a domain/ACM certificate or keep Uptime Kuma private, and test TLS/redirect behavior. The tested endpoint used HTTP only; the app is not running now.
- [ ] Verify SNS subscription and safely exercise CloudWatch alarm conditions including return to OK.
- [ ] Add AWS Budget alerts (for example 50%, 80%, and 100%) and verify notifications.
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

> Continue my Uptime Kuma AWS portfolio project using `docs/session-handoff.md` as the primary handoff and the existing README, OIDC setup, restore-drill, and portfolio-readiness docs as supporting sources. First handle Priority 1: sanitize and reconcile `docs/oidc-setup.md` and `docs/restore-drill.md` for safe publication without breaking the OIDC immutable-subject instructions or overstating test evidence. Make focused commits directly to the existing repo, verify each change, and then summarize what remains before I make the repository public. Do not deploy or destroy AWS resources.
