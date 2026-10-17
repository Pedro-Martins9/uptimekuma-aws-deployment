# Public release and portfolio readiness

**Review date:** 16 October 2026  
**Repository state:** private; application stack offline after successful deployment and restore testing.  
**Completed since the initial checklist:** full-history Gitleaks scan reviewed with no findings reported; Terraform validation workflow passed; teardown audit completed successfully; the separate Terraform-state and application-backup S3 buckets were confirmed to persist.  
**Purpose:** track the remaining work needed to publish the repository safely and present the project accurately on a CV or portfolio.

## 1. Required before changing repository visibility

- [x] **Run and review the full-history Gitleaks scan.** The operator confirmed the scan passed with no findings reported. The workflow `.github/workflows/gitleaks.yml` also continues to scan pushes and pull requests, with scheduled and manual runs available for broader history scans.
- [ ] **If any credential was ever committed, treat it as exposed.** Revoke or rotate it first. Removing it from the latest tree alone does not remove it from Git history.
- [x] **Review the current tracked file tree for sensitive artifacts.** No Terraform state files, plan files, tfvars files, private-key files or credential files are present in the current tree. Keep the .terraform.lock.hcl files; those dependency lock files are intentionally tracked. A clean scan is not a guarantee that a secret was never used or committed; rotate any real credential if there is reason to believe it was exposed.
- [x] **Sanitize the current tree.** Current tracked docs/workflows/backends no longer contain the AWS account ID, state/backup bucket names, EC2 instance IDs or personal IPv4 CIDR. Before using Terraform, configure `AWS_ACCOUNT_ID` and replace the state-bucket placeholders. This does not remove older values from prior commits.
- [x] **Complete AWS cleanup and preserve required storage.** The operator confirmed the teardown audit completed successfully and the separate Terraform-state and application-backup S3 buckets still exist. See section 2.
- [x] **Check workflow results.** The Terraform validation workflow completed successfully, and the full-history Gitleaks scan was reviewed with no findings reported. Re-run these checks after substantive code or workflow changes. The deployment workflow's earlier successful plan/apply is separate from static validation.
- [ ] **Rewrite the default-branch history before public release.** The AWS account ID was present in an older committed Terraform provider/backend/workflow revision. The current tree is sanitized, but historical commits are still reachable. Replace historic account ID and bucket-name literals with placeholders using `git filter-repo`, then force-push the rewritten history from an authenticated local clone and verify every branch/tag/ref. Do not treat a clean Gitleaks scan as proof that identifiers are gone.
- [ ] **Confirm the protected deploy configuration is intentional.** Check the `aws-deploy` GitHub Environment, branch restrictions/reviewer approval, OIDC trust conditions, `AWS_ACCOUNT_ID`, budget variables and `TFPLAN_ENCRYPTION_KEY`. Do not add static AWS access keys.

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

## 3. Remaining engineering work

These items are not required to describe the demonstrated restore, but should remain clearly labelled as outstanding until tested:

- [ ] **Alarm validation:** confirm the SNS email subscription and safely trigger each meaningful CloudWatch alarm, including return to OK. Alarm resources existing in Terraform is not proof that their metric dimensions and thresholds work.
- [ ] **Cost alerts:** configure `BUDGET_ALERT_EMAIL`, review the default $10 USD account-wide monthly budget, apply `terraform/cost-controls/`, then verify email delivery. AWS Budget notifications are alerts, not a hard spending cap.
- [ ] **Actual cost:** after Cost Explorer refreshes, report a project-specific total only if the `Project=uptimekuma` tag is activated for cost allocation. Otherwise report account-wide test-window cost as an upper bound. Be explicit about gross versus credit-offset net cost.
- [ ] **Transport security:** the temporary ALB endpoint used HTTP restricted to a configured IPv4 /32. If operating the dashboard beyond a short test, add a domain, ACM certificate, HTTPS listener and HTTP-to-HTTPS redirect, or keep the interface private. The application is offline now.
- [ ] **Restore evidence:** use [the evidence capture runbook](evidence-capture.md) to measure request-to-healthy-target time, capture exact S3 version/checksum/SSM execution ID and record database-integrity output. Do not claim exact RPO/RTO based on the first drill's timestamps.
- [ ] **Recovery drill quality:** on a future test deployment, create a temporary canary marker, save sanitized output and capture S3 version/hash/SSM execution ID plus timestamps. Run the drill before destroying the test stack.
- [ ] **Teardown reliability:** the previous destroy needed intervention because the Auto Scaling Group still had capacity while ECS was draining. Document a repeatable teardown sequence and test it during a future deployment.
- [ ] **Evidence package:** perform one approved, time-boxed deployment and add sanitized screenshots of ECS service, healthy target, Uptime Kuma, alarm delivery and the approved workflow. Follow `docs/evidence-capture.md`; do not invent a total cost or measured RTO.
- [ ] **License decision:** no LICENSE file is currently tracked. Choose a license if you intend to grant others reuse rights; do not imply an open-source license that has not been selected.

## 4. Final public-release steps

Only do these after section 1 is complete:

- [ ] Update the GitHub repository description to something concise, e.g. **"Terraform-managed Uptime Kuma on ECS/EC2 with OIDC delivery, CloudWatch monitoring and S3 backup/restore."**
- [ ] Add relevant repository topics such as terraform, aws, ecs, devops, github-actions, oidc, and infrastructure-as-code.
- [ ] Review the README top section and all docs once more. Keep the stack status marked **offline/destroyed**, and distinguish demonstrated behavior from planned work.
- [ ] Change visibility manually in GitHub: **Repository → Settings → General → Danger Zone → Change repository visibility → Make public**. Recheck the selected repository name before confirming.
- [ ] After publication, open the repository in a signed-out/private browser window and verify the README, docs, workflow files and links render as expected.

The current GitHub connection available during this review can read and edit repository files, but it does not expose a repository-visibility mutation. The repository therefore remains private until the visibility step above is completed manually.

## 5. Accurate resume / portfolio wording

Use claims like these, which match the recorded tests:

- Built Terraform-managed AWS infrastructure for Uptime Kuma using ECS on EC2, an Auto Scaling Group/capacity provider, an ALB, security groups, IAM roles and Systems Manager—without inbound SSH.
- Implemented S3-backed application recovery using a SQLite-consistent snapshot, SHA-256 verification and a database-integrity gate; validated recovery by replacing the EC2 instance and confirming existing monitor data returned.
- Exercised a GitHub Actions OIDC plan/apply workflow with short-lived AWS credentials, an explicit deployment confirmation, an environment approval gate and a short-lived encrypted Terraform-plan artifact.

Avoid claiming the application is currently live, HTTPS is implemented, alarms have been proven end-to-end, or exact RPO/RTO targets have been measured.
