# Public release and portfolio readiness

**Review date:** 16 October 2026  
**Repository state:** private; application stack offline after successful deployment and restore testing.  
**Completed since the initial checklist:** full-history Gitleaks scan reviewed with no findings reported; Terraform validation workflow passed; teardown audit completed successfully; the separate Terraform-state and application-backup S3 buckets were confirmed to persist.  
**Purpose:** track the remaining work needed to publish the repository safely and present the project accurately on a CV or portfolio.

## 1. Required before changing repository visibility

- [x] **Run and review the full-history Gitleaks scan.** The operator confirmed the scan passed with no findings reported. The workflow `.github/workflows/gitleaks.yml` also continues to scan pushes and pull requests, with scheduled and manual runs available for broader history scans.
- [ ] **If any credential was ever committed, treat it as exposed.** Revoke or rotate it first. Removing it from the latest tree alone does not remove it from Git history.
- [x] **Review the current tracked file tree for sensitive artifacts.** No Terraform state files, plan files, tfvars files, private-key files or credential files are present in the current tree. Keep the .terraform.lock.hcl files; those dependency lock files are intentionally tracked. A clean scan is not a guarantee that a secret was never used or committed; rotate any real credential if there is reason to believe it was exposed.
- [x] **Sanitize supporting documentation.** The OIDC, restore-drill, Terraform backend and deployment workflow examples use placeholders or GitHub variables for account IDs, bucket names, instance IDs and internal monitor names. Configure the `AWS_ACCOUNT_ID` GitHub Actions variable and replace `<TFSTATE_BUCKET>` in both remote backend blocks with the existing state bucket name before running Terraform. Treat this repository as a template until those values are configured.
- [x] **Complete AWS cleanup and preserve required storage.** The operator confirmed the teardown audit completed successfully and the separate Terraform-state and application-backup S3 buckets still exist. See section 2.
- [x] **Check workflow results.** The Terraform validation workflow completed successfully, and the full-history Gitleaks scan was reviewed with no findings reported. Re-run these checks after substantive code or workflow changes. The deployment workflow's earlier successful plan/apply is separate from static validation.
- [ ] **Confirm the protected deploy configuration is intentional.** Check the aws-deploy GitHub Environment, branch restrictions/reviewer approval, OIDC trust conditions, workflow variables and the TFPLAN_ENCRYPTION_KEY secret. Do not add static AWS access keys.

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

These are static configuration checks. They do not deploy resources, prove alarm delivery, or test restore behavior.

## 2. Post-destroy audit — complete

The operator confirmed that the post-destroy audit completed successfully: the application stack is gone, no leftover application resources were found, and the separate Terraform-state and application-backup S3 buckets persist. The application backup and freshness SSM associations were part of the destroyed application stack, so scheduled backups are not running while the app is offline.

If you want to independently re-check the persistent buckets in future, these read-only commands are available:

    aws s3api head-bucket \
      --bucket REPLACE_WITH_EXISTING_TFSTATE_BUCKET \
      --region eu-west-1

    aws s3api head-bucket \
      --bucket REPLACE_WITH_APP_BACKUP_BUCKET \
      --region eu-west-1

    aws s3api list-objects-v2 \
      --bucket REPLACE_WITH_APP_BACKUP_BUCKET \
      --prefix uptimekuma/archives/ \
      --region eu-west-1 \
      --query 'Contents[].{Key:Key,LastModified:LastModified,Size:Size}' \
      --output table

    aws s3api list-objects-v2 \
      --bucket REPLACE_WITH_APP_BACKUP_BUCKET \
      --prefix uptimekuma/checksums/ \
      --region eu-west-1 \
      --query 'Contents[].{Key:Key,LastModified:LastModified,Size:Size}' \
      --output table

Expected decision: retain the state bucket and backup bucket if you intend to preserve the recovery evidence or redeploy. The main application destroy does not manage them. The daily backup and hourly freshness SSM associations belonged to the application stack and were removed during teardown, so automated backups are **not running while the app is offline**.

If you no longer need the buckets, plan their removal separately and deliberately. Do not delete a state bucket while Terraform state still needs it, and do not run the application destroy command from terraform/bootstrap-state/ or terraform/backup-infra/.

## 3. Remaining engineering work

These items are not required to describe the demonstrated restore, but should remain clearly labelled as outstanding until tested:

- [ ] **Alarm validation:** confirm the SNS email subscription and safely trigger each meaningful CloudWatch alarm, including return to OK. Alarm resources existing in Terraform is not proof that their metric dimensions and thresholds work.
- [ ] **Cost alerts:** add AWS Budget notifications at 50%, 80% and 100%, then verify delivery.
- [ ] **Transport security:** the temporary ALB endpoint used HTTP restricted to a configured IPv4 /32. If operating the dashboard beyond a short test, add a domain, ACM certificate, HTTPS listener and HTTP-to-HTTPS redirect, or keep the interface private. The application is offline now.
- [ ] **Restore evidence:** the replacement instance restored the previous wewatch monitor/history and returned healthy. Exact S3 version ID, checksum digest, SSM execution ID, direct SQLite PRAGMA integrity_check output and exact first-healthy timestamp were not captured. Do not claim a precise RPO/RTO based on the available timestamps.
- [ ] **Recovery drill quality:** on a future test deployment, create a temporary RESTORE-DRILL-CANARY marker, save sanitized output and capture S3 version/hash/SSM execution ID plus timestamps. Run the drill before destroying the test stack.
- [ ] **Teardown reliability:** the previous destroy needed intervention because the Auto Scaling Group still had capacity while ECS was draining. Document a repeatable teardown sequence and test it during a future deployment.
- [ ] **Optional evidence:** add sanitized screenshots of the architecture, healthy target, GitHub Actions approval gate, alarm delivery and restore result. Ensure screenshots reveal no personal email addresses, credentials, or unrelated monitored endpoints.
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
