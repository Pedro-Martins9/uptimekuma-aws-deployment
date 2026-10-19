# Public release and portfolio readiness

**Review date:** 19 October 2026  
**Repository state:** private; application stack offline after successful deployment and restore testing.  
**Portfolio publication status: READY TO PUBLISH.** The application remains offline/destroyed; this status means the repository is ready to be shared as an honest portfolio project, not that every future engineering improvement is complete.  
**Security gate reviewed:** the operator reports a clean full-history Gitleaks scan; GitHub reachable-history inspection covered all 138 commits and found no literal AWS account ID or state/backup bucket name; the current tree is sanitized.  
**Purpose:** track the remaining work needed to publish the repository safely and present the project accurately on a CV or portfolio.

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
- [ ] **License decision:** no LICENSE file is currently tracked. Choose a license if you intend to grant others reuse rights; do not imply an open-source license that has not been selected.

## 4. Publish the repository — operator actions

The source is ready to publish. These final GitHub UI actions are still manual:

- [ ] Update the GitHub repository description to something concise, e.g. **"Terraform-managed Uptime Kuma on ECS/EC2 with OIDC delivery, CloudWatch monitoring and S3 backup/restore."**
- [ ] Add relevant repository topics such as terraform, aws, ecs, devops, github-actions, oidc, and infrastructure-as-code.
- [x] Review the README top section. It correctly states that the stack is **offline/destroyed**, distinguishes demonstrated restore behavior from planned work, and does not claim HTTPS, tested alarm delivery, total cost or exact RPO/RTO measurements. Do a quick final review as part of the publication action.
- [ ] Change visibility manually in GitHub: **Repository → Settings → General → Danger Zone → Change repository visibility → Make public**. Recheck the selected repository name before confirming.
- [ ] After publication, open the repository in a signed-out/private browser window and verify the README, docs, workflow files and links render as expected.

The current GitHub connection available during this review can read and edit repository files, but it does not expose a repository-visibility mutation. The repository therefore remains private until the visibility step above is completed manually.

## 5. Accurate resume / portfolio wording

Use claims like these, which match the recorded tests:

- Built Terraform-managed AWS infrastructure for Uptime Kuma using ECS on EC2, an Auto Scaling Group/capacity provider, an ALB, security groups, IAM roles and Systems Manager—without inbound SSH.
- Implemented S3-backed application recovery using a SQLite-consistent snapshot, SHA-256 verification and a database-integrity gate; validated recovery by replacing the EC2 instance and confirming existing monitor data returned.
- Exercised a GitHub Actions OIDC plan/apply workflow with short-lived AWS credentials, an explicit deployment confirmation, an environment approval gate and a short-lived encrypted Terraform-plan artifact.

Avoid claiming the application is currently live, HTTPS is implemented, alarms have been proven end-to-end, or exact RPO/RTO targets have been measured.
