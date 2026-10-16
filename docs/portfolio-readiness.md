# Public release and portfolio readiness

**Review date:** 16 October 2026  
**Repository state:** private; application stack offline after a successful deployment and restore exercise.  
**Purpose:** track the remaining work needed to publish the repository safely and present the project accurately on a CV or portfolio.

## 1. Required before changing repository visibility

- [ ] **Scan the complete Git history for secrets.** Use a dedicated scanner such as Gitleaks against all branches, tags and history, then inspect any findings. Current tracked files do not include Terraform state, .tfvars, plan files or private-key files, but the full history has not been scanned as part of this review.
- [ ] **If any credential was ever committed, treat it as exposed.** Revoke or rotate it first. Removing it from the latest tree alone does not remove it from Git history.
- [ ] **Confirm the repository contains no real Terraform state, plan artifacts, AWS credential files, private keys, personal data or unsanitized screenshots.** Keep the .terraform.lock.hcl files; those dependency lock files are intentionally tracked.
- [ ] **Decide whether to publish the account-specific identifiers.** The Terraform backend names, AWS account ID, bucket names, GitHub owner/repository IDs and sample IAM ARNs appear in the code/docs. These are identifiers, not AWS credentials, but they become more easily discoverable in a public repo. Generalize them if you do not want them public.
- [ ] **Verify AWS cleanup and expected persistent storage.** The application destroy reported 19 resources destroyed, but the final audit was not confirmed in this review. See section 2.
- [ ] **Check the current default-branch Actions results.** Confirm Terraform formatting/validation passes for all three roots. The deployment workflow's earlier successful plan/apply is useful evidence, but does not replace a current validation run after final edits.
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

## 2. Confirm the post-destroy AWS state

Use the intended AWS account and eu-west-1. Check the EC2, ECS, Auto Scaling, Elastic Load Balancing, CloudWatch Logs, EBS and billing views to confirm there are no orphaned project resources. Include unattached volumes and any public IPv4 addresses; do not rely only on the main Terraform destroy summary.

The following CLI commands are read-only checks for the two buckets that are deliberately separate from the application stack:

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
