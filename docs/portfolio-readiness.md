# Public release and portfolio readiness

**Review date:** 21 October 2026  
**Repository state:** public; application stack was redeployed on 20 October 2026; HTTPS and the HTTP-to-HTTPS redirect were last reported working on that date. The README now states that the live demo may be available on request, not that it is continuously available.  
**Portfolio status: COMPLETED — PORTFOLIO RELEASE.** GitHub confirms public visibility. The operator confirms that the S3 backup path, alarm and recovery email notifications, and AWS budget alerts have been tested/configured. Optional screenshots and repository topics remain presentation polish. Runtime status was last reported on 20 October and was not re-probed during this documentation closeout.  
**Security gate reviewed:** the operator reports a clean full-history Gitleaks scan; GitHub reachable-history inspection covered all 138 commits and found no literal AWS account ID or state/backup bucket name; the current tree is sanitized.  
**Purpose:** preserve evidence, limitations and optional presentation improvements for a portfolio project that has reached its completion milestone.

## 1. Publication security gate — PASS

- [x] **Run and review the full-history Gitleaks scan.** The operator confirmed the scan passed with no findings reported. The workflow `.github/workflows/gitleaks.yml` also continues to scan pushes and pull requests, with scheduled and manual runs available for broader history scans.
- [x] **Credential exposure assessment.** The operator reports that full-history `gitleaks detect` completed with no findings. This review did not identify a known credential in reachable history. If separate evidence shows that a real credential was exposed in any commit, log or artifact, revoke or rotate it before publication; a clean scan cannot disprove exposure outside the scanned data.
- [x] **Review the current tracked file tree for sensitive artifacts.** No Terraform state files, plan files, tfvars files, private-key files or credential files are present in the current tree. Keep the .terraform.lock.hcl files; those dependency lock files are intentionally tracked. A clean scan is not a guarantee that a secret was never used or committed; rotate any real credential if there is reason to believe it was exposed.
- [x] **Sanitize the current tree.** Current tracked docs/workflows/backends do not contain concrete AWS account IDs, state/backup bucket names, EC2 instance IDs or personal IPv4 CIDR. The S3 backend blocks use partial configuration (`bucket = ""`); set the existing state bucket name as the GitHub Actions secret `TFSTATE_BUCKET` or pass it through `terraform init -backend-config` locally. Do not reintroduce the bucket name in tracked source. Reachable history is audited separately below.
- [x] **Complete AWS cleanup and preserve required storage.** The operator confirmed the teardown audit completed successfully and the separate Terraform-state and application-backup S3 buckets still exist. See section 2.
- [x] **Check workflow results.** The Terraform validation workflow completed successfully, and the full-history Gitleaks scan was reviewed with no findings reported. Re-run these checks after substantive code or workflow changes. The deployment workflow's earlier successful plan/apply is separate from static validation.
- [x] **Audit reachable Git history for account-specific identifiers (19 October 2026).** I checked all 138 commits reachable from `main` via GitHub's commit API and searched commit diffs for concrete 12-digit AWS account IDs and literal state/backup bucket names; none were found. The repository refs endpoint reports only `refs/heads/main`, with no tag refs. The operator also reports that `gitleaks detect` completed with no findings. No further history rewrite was performed from this session because the reachable-history audit found no targeted literals to remove. This check covers history reachable through current GitHub refs. It cannot erase copies in other local clones or guarantee immediate removal of GitHub's unreachable-object caches. Those limitations do not block sharing the sanitized portfolio source; keep any old clones private and do not restore the removed identifiers.
- [x] **Review the deployment workflow safeguards in source.** The workflow limits plan/apply to `main`, requires the explicit `DEPLOY` confirmation for apply, uses the `aws-deploy` GitHub Environment, short-lived OIDC credentials and an encrypted one-day plan artifact; no static AWS access keys are embedded. The connected GitHub interface cannot verify the environment's configured reviewers, repository variables/secrets or the AWS IAM trust policies. The connected GitHub interface cannot independently confirm those settings. Review them as operational hardening, especially before the next deployment or any permission change.

### Local checks

Run from the repository root with Terraform installed:

    terraform fmt -check -recursive

Validate each root without connecting to the remote state backend:

    terraform -chdir=terraform init -backend=false -input=false -lockfile=readonly
    terraform -chdir=terraform validate -no-color

    terraform -chdir=terraform/bootstrap-state init -backend=false -input=false -lockfile=readonly
    terraform -chdir=terraform/bootstrap-state validate -no-color

    terraform -chdir=terraform/backup-infra init -backend=false -input=false -lockfile=readonly
    terraform -chdir=terraform/backup-infra validate -no-color

    terraform -chdir=terraform/cost-controls init -backend=false -input=false -lockfile=readonly
    terraform -chdir=terraform/cost-controls validate -no-color

These are static configuration checks. They do not deploy resources, prove alarm delivery, or test restore behavior.

## 2. Post-destroy audit — complete

The operator confirmed that the post-destroy audit completed successfully for the earlier teardown. On 20 October 2026, deployment workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) subsequently created 47 resources, with 0 changes and 0 destroys. The current application stack is deployed again, and the operator reports that the HTTPS hostname works and HTTP redirects to HTTPS. The separate Terraform-state and application-backup S3 buckets persist. The commands below use placeholders for the bucket names and region. Backup and freshness SSM associations were recreated by the application deployment. The operator has now confirmed that `BackupFresh` datapoints are visible under the alarm's expected dimensions and the freshness alarm has cleared after the metric-dimension fix. The operator confirms S3 backups have been tested successfully. No repeat backup or restore test is required solely for closeout. The newest archive/checksum pair was not independently inspected during this repository-only review; a sanitized listing is optional supporting evidence rather than a blocker.

If you want to independently re-check the persistent buckets in future, these read-only commands are available:

    aws s3api head-bucket \
      --bucket <TFSTATE_BUCKET> \
      --region <AWS_REGION>

    aws s3api head-bucket \
      --bucket <APP_BACKUP_BUCKET> \
      --region <AWS_REGION>

    aws s3api list-objects-v2 \
      --bucket <APP_BACKUP_BUCKET> \
      --prefix uptimekuma/archives/ \
      --region <AWS_REGION> \
      --query 'Contents[].{Key:Key,LastModified:LastModified,Size:Size}' \
      --output table

    aws s3api list-objects-v2 \
      --bucket <APP_BACKUP_BUCKET> \
      --prefix uptimekuma/checksums/ \
      --region <AWS_REGION> \
      --query 'Contents[].{Key:Key,LastModified:LastModified,Size:Size}' \
      --output table

Expected decision: retain the state bucket and backup bucket while their state and recovery evidence are needed. The main application destroy does not manage them. The hourly freshness association is now publishing datapoints under `Project=uptimekuma`, and the operator reports that the backup-freshness alarm has cleared. Verify the latest daily archive and matching checksum object separately before considering the complete automated backup chain validated.

If you no longer need the buckets, plan their removal separately and deliberately. Do not delete a state bucket while Terraform state still needs it, and do not run the application destroy command from terraform/bootstrap-state/ or terraform/backup-infra/.

## 3. Final closeout status — 21 October 2026

The operator confirms that S3 backups and alarm email notifications have been tested successfully and that AWS Budgets are configured. These are operator-confirmed results; this session did not independently query live AWS resources. Do not repeat successful live tests solely to create screenshots.

- [x] **Application deployment:** [Terraform deployment run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) succeeded (47 resources added, 0 changed, 0 destroyed). Current service health and public HTTPS were reported by the operator on 20 October; make a fresh availability claim only after a fresh live check.
- [x] **Backup and recovery:** the restore drill is documented in [restore-drill.md](restore-drill.md), and the operator confirms the S3 backup path works. Exact RPO/RTO, object version IDs, and direct SQLite integrity output were not captured in the original drill. These are limits on measurement precision, not blockers for accurately describing the demonstrated restore.
- [x] **Alarm delivery:** the operator confirms alert and recovery email tests passed. [Deployment run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112) records SNS/email alarm wiring. Keep the claim limited to the alarm paths actually tested.
- [x] **Backup freshness metric:** the fix in [`terraform/backup.tf`](../terraform/backup.tf) was deployed in [run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374); the operator confirms the expected datapoints are visible and the freshness alarm cleared.
- [x] **Dynamic host-port path:** operationally verified on 20 October 2026; see the handoff. No further port investigation is needed unless connectivity problems occur or networking changes.
- [x] **Budget alerts:** the operator confirms budget alerts are configured. A €10 configured threshold is not evidence that €10 has been spent; preserve the budget period, threshold type (actual/forecasted), currency and current spend when interpreting a notification.
- [x] **Reported run cost:** the operator estimates the combined cost of the project runs at approximately €0.20. Treat this as an estimate until supported by a Cost Explorer or billing export with a defined date range and cost treatment.
- [x] **Secret scanning:** Gitleaks workflow is enabled and the final closeout scan passes on the current documentation head; see the [Gitleaks workflow history](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/workflows/gitleaks.yml).
- [x] **Terraform validation:** [the latest validation run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358) passed on the latest Terraform-code commit. Commits since then changed documentation only.
- [ ] **Optional visual evidence:** capture a small sanitized screenshot pack and/or a 2–3 minute demo if it materially improves the portfolio. Do not redeploy or rerun successful alarm/backup tests solely to create screenshots.
- [ ] **Optional cost evidence:** only publish a cost number after collecting Cost Explorer or billing evidence with the date range, currency, cost metric, attribution method and credits/refunds treatment. The README omits the earlier €0.20 estimate until it can be substantiated.
- [ ] **Optional repository topics:** GitHub metadata shows the description is already set, but no topics are configured. Add `aws`, `terraform`, `ecs`, `devops`, `github-actions`, `oidc`, and `infrastructure-as-code` if you want the final presentation polish.
- [ ] **Final infrastructure disposition:** keep the app deployed if the live endpoint is useful for demonstrating the project; otherwise perform the reviewed main-root teardown and audit remaining resources. Never destroy the persistent state bucket or backup-infrastructure root as part of routine application teardown.

**Recommended finish line:** the project can be labelled **COMPLETED — PORTFOLIO RELEASE** now, provided the cost statement stays qualified and existing operational checks are accurately attributed to the operator. The optional screenshots/topics improve presentation but are not engineering blockers.

## 4. Post-publication housekeeping

The repository is now public; GitHub's repository metadata confirms `visibility: public`. The remaining tasks are presentation polish and metadata, not a visibility blocker.

- [x] **Change repository visibility to public.** Completed 19 October 2026 and verified through GitHub repository metadata.
- [ ] **Verify public rendering while signed out.** Open the repository in a private/signed-out browser window and check the README, docs, workflow files, architecture diagram and relative links. API metadata confirms public visibility, but the signed-out browser review has not been independently confirmed here.
- [x] **Set a repository description.** GitHub metadata currently shows: "Terraform-managed Uptime Kuma on ECS/EC2 with AWS OIDC deployments, CloudWatch monitoring, and S3 backup/restore."
- [ ] **Add repository topics.** No topics are currently configured. Suggested topics: `aws`, `terraform`, `ecs`, `devops`, `github-actions`, `oidc`, and `infrastructure-as-code`.
- [ ] **Add demo evidence.** A short 2–3 minute walkthrough and 3–4 sanitized screenshots would make the project easier to evaluate at a glance. Do not repeat successful backup or alarm tests solely to create evidence.
- [x] **Add a license.** Added the Apache License 2.0 in the root `LICENSE` file and linked it from the README. It licenses this project's original work; third-party tools and dependencies remain under their respective licenses.

Repository topics, pinning and profile links should be completed as GitHub/profile housekeeping after the evidence and README are in place. The available GitHub connection can update repository files but does not expose topics or pinning for mutation.

## 5. Accurate resume / portfolio wording

Use claims like these, which match the recorded tests:

- Built Terraform-managed AWS infrastructure for Uptime Kuma using ECS on EC2, an Auto Scaling Group/capacity provider, an ALB, security groups, IAM roles and Systems Manager—without inbound SSH.
- Implemented S3-backed application recovery using a SQLite-consistent snapshot, SHA-256 verification and a database-integrity gate; validated recovery by replacing the EC2 instance and confirming existing monitor data returned.
- Exercised a GitHub Actions OIDC plan/apply workflow with short-lived AWS credentials, an explicit deployment confirmation, an environment approval gate and a short-lived encrypted Terraform-plan artifact.

Avoid unqualified present-tense availability claims without a fresh check; describe the hostname, HTTPS, and infrastructure status as operator-verified at the time of the check. The operator confirms alarm and recovery email delivery tests are complete. Do not imply that every individual alarm's metric threshold was separately exercised unless the evidence proves it. Do not claim exact measured RPO/RTO or publish the approximate €0.20 estimate as a verified billing total. The recruiter-facing README omits the figure until it is supported by billing evidence.
