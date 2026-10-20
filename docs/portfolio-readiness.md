# Public release and portfolio readiness

**Review date:** 20 October 2026  
**Repository state:** public; application stack redeployed on 20 October 2026; the operator reports that the HTTPS hostname works and HTTP redirects to HTTPS.  
**Portfolio publication status: PUBLISHED.** GitHub repository metadata confirms public visibility. The application is deployed again after the 20 October 2026 Terraform apply; publication and reported HTTPS access do not imply that all operational checks are complete.  
**Security gate reviewed:** the operator reports a clean full-history Gitleaks scan; GitHub reachable-history inspection covered all 138 commits and found no literal AWS account ID or state/backup bucket name; the current tree is sanitized.  
**Purpose:** track remaining portfolio presentation and engineering hardening work now that the repository is public.

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

The operator confirmed that the post-destroy audit completed successfully for the earlier teardown. On 20 October 2026, deployment workflow [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) subsequently created 47 resources, with 0 changes and 0 destroys. The current application stack is deployed again, and the operator reports that the HTTPS hostname works and HTTP redirects to HTTPS. The separate Terraform-state and application-backup S3 buckets persist. The commands below use placeholders for the bucket names and region. Backup and freshness SSM associations were recreated by the application deployment; verify a successful association execution and an archive plus checksum in S3 before treating scheduled backups as validated.

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

Expected decision: retain the state bucket and backup bucket while their state and recovery evidence are needed. The main application destroy does not manage them. The daily backup and hourly freshness SSM associations were recreated by the 20 October deployment; verify a recent successful execution and matching archive/checksum objects before considering automated backup healthy.

If you no longer need the buckets, plan their removal separately and deliberately. Do not delete a state bucket while Terraform state still needs it, and do not run the application destroy command from terraform/bootstrap-state/ or terraform/backup-infra/.

## 3. Follow-up engineering work — not publication blockers

These items improve the deployment or evidence package but are not required to publish an honest portfolio account of what was built and tested. Keep them clearly labelled as outstanding until tested:

- [ ] **SNS email and alarm validation:** the current apply did not create an SNS topic/subscription (the deployment workflow only passes `vars.ALERT_EMAIL`; when that repository Actions variable is blank, Terraform sets no alarm actions). Set repository Actions variable `ALERT_EMAIL` to the intended recipient, run a fresh `application` plan and confirm it proposes an SNS topic/email subscription plus alarm-action updates, then use the gated deploy workflow. Confirm the SNS email subscription from your inbox, test publishing to the topic, then test an alarm state transition and recovery. Alarm resources existing in Terraform is not proof that notifications work.
- [ ] **Cost alerts:** configure `BUDGET_ALERT_EMAIL`, review the default $10 USD account-wide monthly budget, apply `terraform/cost-controls/`, then verify email delivery. AWS Budget notifications are alerts, not a hard spending cap.
- [ ] **Actual cost:** after Cost Explorer refreshes, report a project-specific total only if the `Project=uptimekuma` tag is activated for cost allocation. Otherwise report account-wide test-window cost as an upper bound. Be explicit about gross versus credit-offset net cost.
- [x] **Deploy public HTTPS endpoint:** Terraform deployment [run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) completed successfully (47 resources added, 0 changed, 0 destroyed). The operator reports that `uptime.pedromartins9.me` routes to the application and HTTP redirects to HTTPS. The remaining checks are certificate validity in the browser, target health, login, alarms and backup execution. Keep strong, unique Uptime Kuma credentials because the login page is internet-accessible.
- [ ] **Dynamic host-port verification (post-deployment):** verify the new EC2 instance's ephemeral-port range, ECS Docker bridge dynamic host-port allocation and ALB target health. Security-group rules permit TCP 32768–65535; a prior SSM check reported 32768–60999. That range covers the previously observed host range, but confirm the new instance configuration and target registration before closing this item.
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

Avoid claiming the application is currently live, HTTPS has been deployed and tested, alarms have been proven end-to-end, or exact RPO/RTO targets have been measured.
