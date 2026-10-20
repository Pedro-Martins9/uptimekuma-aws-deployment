# Session handoff — Uptime Kuma AWS portfolio project

**Last updated:** 20 October 2026  
**Repository:** https://github.com/Pedro-Martins9/uptimekuma-aws-deployment  
**Default branch:** `main`  
**Current visibility:** public (verified through GitHub repository metadata)  
**Current app status:** redeployed on 20 October 2026. Terraform workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) succeeded (47 added, 0 changed, 0 destroyed). The operator reports that `uptime.pedromartins9.me` serves the application and HTTP redirects to HTTPS. Follow-up checks remain for target health, dynamic port mapping, alarms and a successful backup execution.  
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
- EC2 previously reported ephemeral range 32768–60999, while the ALB/ECS security-group rules allow TCP 32768–65535. This range comparison alone does not prove ECS dynamic host-port allocation and ALB health checks are correct; revisit and verify the configured port ranges/mapping before the next deployment.
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
- [ ] Keep the application offline until an explicit test window and acceptable spend have been agreed.

### Priority 3 — one approved, time-boxed engineering evidence deployment
- [ ] **HTTPS Terraform is in source but not deployed:** default hostname is `uptime.pedromartins9.me`; `terraform/certificate.tf` looks up an existing issued ACM certificate and `terraform/loadbalancer.tf` configures HTTPS on 443 plus an HTTP-to-HTTPS redirect on 80. The ALB will be public on IPv4 TCP 80/443; ECS dynamic host-port ingress must remain limited to the ALB security group. Do not plan until ACM status is `ISSUED` in `eu-west-1`, the certificate covers the hostname. The default primary-domain lookup is `uptime.pedromartins9.me`; if the issued certificate has a different primary domain, set GitHub variable `ACM_CERTIFICATE_LOOKUP_DOMAIN` to that exact domain. An apex-only certificate without the subdomain will not work. After an approved apply, create the external DNS CNAME `uptime` pointing to `terraform output -raw alb_dns_name`. Use strong, unique Uptime Kuma credentials because the login page will be internet-accessible.
- [ ] Verify SNS subscription, exercise meaningful CloudWatch alarm transitions to ALARM and back to OK, and separately inspect metric dimensions/threshold behavior.
- [ ] Repeat the restore drill with a canary monitor and collect the exact S3 version ID, checksum digest, SSM execution ID, direct SQLite integrity output, termination-request time and first healthy replacement-target time. Record dashboard usability separately; do not claim exact RPO/RTO until directly measured.
- [ ] Capture sanitized ECS, ALB, dashboard/restore, alarm-email, and GitHub Actions evidence.
- [ ] After Cost Explorer refreshes, report a cost only with its period, metric, attribution/filter, currency and gross-versus-credit-offset treatment. Include retained S3 costs and don't present account-wide costs as project-only costs.
- [ ] Improve and test the teardown procedure, which previously required reducing ASG desired capacity to zero and replanning. Audit the account after teardown and preserve the separate state/backup roots.

## 6. Technical guardrails

- Do not claim HTTPS is live or tested: the Terraform listener/redirect configuration is committed but has not been applied.
- Do not claim alarm notifications are proven end-to-end.
- Do not claim exact measured RPO or RTO.
- Do not claim the application is live; it was destroyed after the successful drill.
- The state and backup buckets persist and may still incur cost.
- Never commit Terraform state, plan artifacts, `.tfvars`, credentials, or private keys.
- Before a future deployment, inspect the entire Terraform plan and verify public ALB ingress is limited to IPv4 TCP 80/443. Keep ECS dynamic host ports restricted to the ALB security group. Revisit the EC2 host ephemeral-port range and confirm it matches the dynamic host-port security-group rules before deployment; this check is still outstanding.
- If Terraform is initialized, avoid running apply or destroy until the target AWS identity, backend and intended action are explicitly confirmed.

## 7. Quick prompt for the next ChatGPT session

> Continue the Uptime Kuma AWS portfolio project from this handoff. The repository is PUBLIC (verified via GitHub metadata); the application stack is offline/destroyed and the separate Terraform state and app-backup S3 buckets remain. The current tree was sanitized, the operator reported a clean full-history Gitleaks scan, and the reachable-history audit covered 138 commits with no literal AWS account ID or static state/backup bucket names found. The latest Gitleaks push runs are passing. Do not re-introduce a history-rewrite blocker without new evidence. First finish public-facing housekeeping: verify rendering while signed out and set the GitHub repository description and topics (currently empty). Apache License 2.0 is already committed in `LICENSE` and linked from the README. A domain is now available (`pedromartins9.me`); the proposed dashboard hostname is `uptime.pedromartins9.me`, Terraform now has the ACM lookup, HTTPS listener and HTTP-to-HTTPS redirect in source, but the DNS record has not been routed to the ALB and no AWS apply has occurred. Before any redeployment, review persistent S3 storage, enable and verify cost alerts if approved, and verify GitHub Environment/OIDC/IAM deployment settings. The Terraform source selects an existing issued ACM certificate using `acm_certificate_lookup_domain` (defaults to `domain_name`) and defines HTTPS/redirect listeners; do not plan until the certificate is `ISSUED` in `eu-west-1` and covers that hostname. If its ACM primary domain differs from the service hostname, configure repository variable `ACM_CERTIFICATE_LOOKUP_DOMAIN`. After an approved apply, point the external DNS CNAME to the ALB output. Public access is intentionally allowed on IPv4 80/443, while ECS host ports must remain restricted to the ALB security group. Use strong, unique Uptime Kuma admin credentials. Only proceed with an explicitly approved test window and spend. HTTPS, alarm delivery, precise RPO/RTO, demo evidence, Cost Explorer reporting, and teardown reliability remain engineering follow-ups, not publication blockers.
