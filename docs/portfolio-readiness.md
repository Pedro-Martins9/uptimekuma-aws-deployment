# Public release and portfolio readiness

**Review date:** 19 October 2026  
**Repository state:** public; application stack offline after successful deployment and restore testing.  
**Portfolio publication status: PUBLISHED.** GitHub repository metadata confirms public visibility. The application remains offline/destroyed; publication does not imply that every follow-up engineering improvement is complete.  
**Security gate reviewed:** the operator reports a clean full-history Gitleaks scan; GitHub reachable-history inspection covered all 138 commits and found no literal AWS account ID or state/backup bucket name; the current tree is sanitized.  
**Purpose:** track remaining portfolio presentation and engineering hardening work now that the repository is public.

## 1. Publication security gate — PASS

- [x] **Run and review the full-history Gitleaks scan.** The operator confirmed the scan passed with no findings reported. The workflow `.github/workflows/gitleaks.yml` also continues to scan pushes and pull requests, with scheduled and manual runs available for broader history scans.
- [x] **Credential exposure assessment.** The operator reports that full-history `gitleaks detect` completed with no findings. This review did not identify a known credential in reachable history. If separate evidence shows that a real credential was exposed in any commit, log or artifact, revoke or rotate it before publication; a clean scan cannot disprove exposure outside the scanned data.
- [x] **Review the current tracked file tree for sensitive artifacts.** No Terraform state files, plan files, tfvars files, private-key files or credential files are present in the current tree. Keep the .terraform.lock.hcl files; those dependency lock files are intentionally tracked. A clean scan is not a guarantee that a secret was never used or committed; rotate any real credential if there is reason to believe it was exposed.
- [x] **Sanitize the current tree.** Current tracked docs/workflows/backends no longer contain concrete AWS account IDs, state/backup bucket names, EC2 instance IDs or personal IPv4 CIDR. Configure `AWS_ACCOUNT_ID` and replace state-bucket placeholders only in your local deployment configuration; do not commit account-specific values. Reachable history is audited separately below.
- [x] **Complete AWS cleanup and preserve required storage.** The operator confirmed the teardown audit completed successfully and the separate Terraform-state and application-backup S3 buckets still exist. See section 2.
- [x] **Check workflow results.** The Terraform validation workflow completed successfully, and the full-history Gitleaks scan was reviewed with no findings reported. Re-run these checks after substantive code or workflow changes. The deployment workflow's earlier successful plan/apply is separate from static validation.
- [x] **Audit reachable Git history for account-specific identifiers (19 October 2026).** I checked all 138 commits reachable from `main` via GitHub's commit API and searched commit diffs for concrete 12-digit AWS account IDs and literal state/backup bucket names; none were found. The repository refs endpoint reports only `refs/heads/main`, with no tag refs. The operator also reports that `gitleaks detect` completed with no findings. No further history rewrite was performed from this session because the reachable-history audit found no targeted literals to remove. This check covers history reachable through current GitHub refs. It cannot erase copies in other local clones or guarantee immediate removal of GitHub's unreachable-object caches. Those limitations do not block sharing the sanitized portfolio source; keep any old clones private and do not restore the removed identifiers.
- [x] **Review the deployment workflow safeguards in source.** The workflow limits plan/apply to `main`, requires the explicit `DEPLOY` confirmation for apply, uses the `aws-deploy` GitHub Environment, short-lived OIDC credentials and an encrypted one-day plan artifact; no static AWS access keys are embedded. The connected GitHub interface cannot verify the environment's configured reviewers, repository variables/secrets or the AWS IAM trust policies. Those settings must be verified before any future AWS deployment, but are not a blocker to publishing this currently offline portfolio repository.

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

The operator confirmed that the post-destroy audit completed successfully: the application stack is gone, no leftover application resources were found, and the separate Terraform-state and application-backup S3 buckets persist. The commands below use placeholders for the bucket names and region. The application backup and freshness SSM associations were part of the destroyed application stack, so scheduled backups are not running while the app is offline.

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

Expected decision: retain the state bucket and backup bucket if you intend to preserve the recovery evidence or redeploy. The main application destroy does not manage them. The daily backup and hourly freshness SSM associations belonged to the application stack and were removed during teardown, so automated backups are **not running while the app is offline**.

If you no longer need the buckets, plan their removal separately and deliberately. Do not delete a state bucket while Terraform state still needs it, and do not run the application destroy command from terraform/bootstrap-state/ or terraform/backup-infra/.

## 3. Follow-up engineering work — not publication blockers

These items improve the deployment or evidence package but are not required to publish an honest portfolio account of what was built and tested. Keep them clearly labelled as outstanding until tested:

- [ ] **Alarm validation:** confirm the SNS email subscription and safely trigger each meaningful CloudWatch alarm, including return to OK. Alarm resources existing in Terraform is not proof that their metric dimensions and thresholds work.
- [ ] **Cost alerts:** configure `BUDGET_ALERT_EMAIL`, review the default $10 USD account-wide monthly budget, apply `terraform/cost-controls/`, then verify email delivery. AWS Budget notifications are alerts, not a hard spending cap.
- [ ] **Actual cost:** after Cost Explorer refreshes, report a project-specific total only if the `Project=uptimekuma` tag is activated for cost allocation. Otherwise report account-wide test-window cost as an upper bound. Be explicit about gross versus credit-offset net cost.
- [ ] **Transport security:** the temporary ALB endpoint used HTTP restricted to a configured IPv4 /32. If operating the dashboard beyond a short test, add a domain, ACM certificate, HTTPS listener and HTTP-to-HTTPS redirect, or keep the interface private. The application is offline now.
- [ ] **Restore evidence:** use [the evidence capture runbook](evidence-capture.md) to measure request-to-healthy-target time, capture exact S3 version/checksum/SSM execution ID and record database-integrity output. Do not claim exact RPO/RTO based on the first drill's timestamps.
- [ ] **Recovery drill quality:** on a future test deployment, create a temporary canary marker, save sanitized output and capture S3 version/hash/SSM execution ID plus timestamps. Run the drill before destroying the test stack.
- [ ] **Teardown reliability:** the previous destroy needed intervention because the Auto Scaling Group still had capacity while ECS was draining. Document a repeatable teardown sequence and test it during a future deployment.
- [ ] **Evidence package:** perform one approved, time-boxed deployment and add sanitized screenshots of ECS service, healthy target, Uptime Kuma, alarm delivery and the approved workflow. Follow `docs/evidence-capture.md`; do not invent a total cost or measured RTO.

## 4. Post-publication housekeeping

The repository is now public; GitHub's repository metadata confirms `visibility: public`. The remaining tasks are presentation checks and metadata, not a visibility blocker.

- [x] **Change repository visibility to public.** Completed 19 October 2026 and verified through GitHub repository metadata.
- [ ] **Verify public rendering while signed out.** Open the repository in a private/signed-out browser window and check the README, docs, workflow files, architecture diagram and relative links. API metadata confirms public visibility, but the signed-out browser review has not been independently confirmed here.
- [ ] **Set a repository description.** The current GitHub metadata has an empty description. Suggested text: **"Terraform-managed Uptime Kuma on ECS/EC2 with OIDC delivery, CloudWatch monitoring and S3 backup/restore."**
- [ ] **Add repository topics.** No topics are currently configured. Suggested topics: `aws`, `terraform`, `ecs`, `devops`, `github-actions`, `oidc`, and `infrastructure-as-code`.
- [x] **Add a license.** Added the Apache License 2.0 in the root `LICENSE` file and linked it from the README. It licenses this project's original work; third-party tools and dependencies remain under their respective licenses.

Repository settings such as the description and topics must be changed manually; the available GitHub connection used for this review can read and update repository files but does not expose those settings for mutation.

## 5. Accurate resume / portfolio wording

Use claims like these, which match the recorded tests:

- Built Terraform-managed AWS infrastructure for Uptime Kuma using ECS on EC2, an Auto Scaling Group/capacity provider, an ALB, security groups, IAM roles and Systems Manager—without inbound SSH.
- Implemented S3-backed application recovery using a SQLite-consistent snapshot, SHA-256 verification and a database-integrity gate; validated recovery by replacing the EC2 instance and confirming existing monitor data returned.
- Exercised a GitHub Actions OIDC plan/apply workflow with short-lived AWS credentials, an explicit deployment confirmation, an environment approval gate and a short-lived encrypted Terraform-plan artifact.

Avoid claiming the application is currently live, HTTPS is implemented, alarms have been proven end-to-end, or exact RPO/RTO targets have been measured.
