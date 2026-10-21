# Portfolio evidence capture

This runbook supports evidence capture for the deployment completed on 20 October 2026. The operator confirms S3 backups and alarm email tests are successful. No new deployment or repeated backup/alarm test is needed just to finish the portfolio. Capture the smallest useful sanitized evidence set from existing logs and read-only console views; the pre-deployment checklist below is for future redeployments only.

## Pre-deployment checklist (for future redeployments)

- [ ] Agree the test window and acceptable spend before applying anything. Review the entire Terraform plan and confirm the target AWS account.
- [ ] Configure the existing remote-state bucket name in each backend block and set `TF_VAR_aws_account_id`. For GitHub Actions, configure `AWS_ACCOUNT_ID`, the role ARNs, `TFPLAN_ENCRYPTION_KEY`, `BUDGET_ALERT_EMAIL` and (if needed) `MONTHLY_BUDGET_LIMIT_USD`.
- [ ] Confirm the intended public exposure: the ALB accepts public IPv4 traffic on TCP 80/443, HTTP redirects to HTTPS, and ECS dynamic host-port ingress is limited to the ALB security group. Use strong, unique Uptime Kuma credentials because the login page will be internet-accessible.
- [x] **Dynamic host-port path operationally verified on 20 October 2026:** the ECS task mapped container port 3001 to host port 32768, security groups permit TCP 32768–65535, and the previously observed kernel range 32768–60999 is covered. The application was reachable through the ALB. No further investigation is required unless connectivity issues arise or the networking configuration changes.
- [ ] The default dashboard hostname is `uptime.pedromartins9.me` (override using `TF_VAR_domain_name` locally or the `UPTIME_KUMA_DOMAIN_NAME` GitHub Actions repository variable). Verify that the ACM certificate is **ISSUED in `eu-west-1`** and covers this hostname. By default, the lookup matches the ACM certificate primary domain exactly to `uptime.pedromartins9.me`. If the certificate has a different primary domain, configure GitHub Actions variable `ACM_CERTIFICATE_LOOKUP_DOMAIN` (or local Terraform variable `acm_certificate_lookup_domain`) with that exact primary domain. The issued certificate must still cover `uptime.pedromartins9.me`; an apex-only certificate without the subdomain will fail TLS hostname validation. Terraform reuses the existing certificate rather than creating a duplicate.
- [ ] Record the start time in UTC, the tested commit SHA, region, and planned teardown time in private notes. Do not publish AWS account IDs, ARNs, IP addresses, email addresses, full target URLs, or monitor names that reveal private details.

## DNS routing after the ALB is created

The DNS zone is not managed by this Terraform root. After an approved apply, retrieve the load balancer target:

```bash
terraform -chdir=terraform output -raw alb_dns_name
```

In the DNS provider authoritative for `pedromartins9.me`, create a CNAME record with:

- Host/name: `uptime`
- Target/value: the exact ALB DNS name returned above (hostname only; no scheme or path)
- TTL: provider default/automatic is fine

Keep the ACM DNS-validation CNAME record in place; ACM uses it for certificate validation and managed renewal. Do not create the application CNAME before the ALB exists unless its DNS target is already known. Verify that the domain points to the ALB before testing browser HTTPS and the HTTP redirect.

## Screenshots to capture

Use PNG screenshots that show enough of the AWS/GitHub console to establish the result, but hide account IDs, unrelated resources and personal information.

1. **ECS service:** desired/running task counts, service status and recent steady-state events.
2. **ALB target health:** the Uptime Kuma target registered and healthy.
3. **Application:** Uptime Kuma dashboard with harmless test monitors and restored history visible. Use a controlled endpoint; redact private monitor URLs.
4. **Recovery proof:** replacement-instance restore-success log and the restored dashboard/monitor history.
5. **Alarm delivery:** the test alarm email with identifying details redacted, plus CloudWatch showing the alarm returning to OK.
6. **Pipeline:** successful GitHub Actions validation and the reviewed, approval-gated deployment run.
7. **HTTPS deployment evidence:** capture the issued ACM certificate, HTTPS listener, HTTP-to-HTTPS redirect, public DNS resolution and successful HTTPS access after the approved apply.
8. **Cost evidence:** Cost Explorer date range, cost metric and tag/service filter, with billing-account details redacted where appropriate.

Keep unredacted operational evidence privately; only publish the sanitized copies.

## Measure recovery instead of estimating it

Follow the timed replacement procedure in [the restore drill](restore-drill.md). It records the time immediately before requesting replacement and then waits for the replacement instance's ALB target to become healthy, rather than accidentally timing the old instance's still-healthy target.

Record these exact values in private test notes and then sanitize them for publication:

- Termination-request start timestamp (UTC).
- Replacement instance ID, stored privately.
- First healthy target timestamp (UTC) for the replacement instance.
- Request-to-healthy-target duration in seconds.
- Restore-success log timestamp and result.
- Whether the existing monitor configuration/history returned and the dashboard was usable.
- S3 archive key, version ID and SHA-256 digest.
- SQLite `PRAGMA integrity_check` output, if directly captured.
- Teardown start/end, teardown result and post-destroy audit.

The request-to-healthy-target duration is a measured recovery indicator, not necessarily a complete RTO if the application needs additional time to become usable. Record the dashboard verification separately.

## Prove alarm delivery

Use only the isolated test deployment. First verify the SNS email subscription is confirmed. The existing ALB unhealthy-target alarm can be put into a temporary ALARM state to exercise the notification action, then returned to OK:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name uptimekuma-alb-unhealthy-targets \
  --state-value ALARM \
  --state-reason "Portfolio notification-delivery test" \
  --region eu-west-1

# Confirm the test email arrived, then return the alarm to OK:
aws cloudwatch set-alarm-state \
  --alarm-name uptimekuma-alb-unhealthy-targets \
  --state-value OK \
  --state-reason "Portfolio notification-delivery test completed" \
  --region eu-west-1
```

This checks that the alarm action can send email. It does **not** prove the alarm's metric dimensions or threshold logic are correct. Separately inspect the metric and alarm history during the test, and record exactly what was tested. Do not deliberately break a production workload to generate an alarm.

## Calculate and report cost honestly

After Cost Explorer has refreshed, select the date range covering the deployment and teardown, then review the cost metric, credits and tag filter.

- The Terraform resources carry a `Project=uptimekuma` tag, but AWS user-defined cost-allocation tags must be activated before they appear in Cost Explorer. Activation and reporting can take time; see [AWS instructions for activating cost-allocation tags](https://docs.aws.amazon.com/us_en/awsaccountbilling/latest/aboutv2/activating-tags.html).
- Cost Explorer data is usually refreshed at least every 24 hours, but some data may arrive later; see [AWS Cost Explorer overview](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html).
- If the `Project=uptimekuma` tag was not active for the test period, do not call the total account cost a project-only total. Report it as an account-wide cost over the test window, or leave the project cost unpublished until it can be attributed reliably.
- Record whether the figure is gross cost before credits or net cost after credits. The Terraform budget deliberately excludes credits, whereas Cost Explorer's displayed metric and settings can change the total.
- Include persistent S3 state/backup storage in the project-cost discussion, because those buckets remain after the application stack is destroyed.

Do not invent a cost figure from instance prices or a short test duration. Record the exact date range, metric, tag/filter, currency and value from the billing report.

## Recorded closeout status — 21 October 2026

| Item | Current status | Evidence / limit |
|---|---|---|
| Application deployment | Pass | [Terraform deployment run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090); 47 added, 0 changed, 0 destroyed |
| Backup freshness fix | Pass | [Terraform deployment run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374); operator confirms datapoints appeared and the freshness alarm cleared |
| ECS / ALB health | Operator-reported pass | One running task and a healthy target were reported on 20 October 2026; not independently re-probed during this closeout |
| HTTPS and HTTP redirect | Operator-reported pass | Reported working on 20 October 2026; capture a sanitized browser view only if a visual portfolio image is needed |
| Backup and recovery | Pass, with measurement limits | [Restore-drill record](restore-drill.md) documents restoration of previous monitor data after instance replacement. Exact RPO/RTO and direct SQLite output were not recorded |
| S3 backup test | Operator-confirmed pass | The operator confirms backup tests are working. The newest archive/checksum object pair was not independently inspected in this documentation-only session |
| Alert and recovery email | Operator-confirmed pass | The operator confirms both are tested; deployment wiring is documented in [run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112) |
| Budget alerts | Operator-confirmed configured | A budget threshold (for example €10) is not the same as actual spend; record whether a notification is actual- or forecast-based |
| Reported test/deployment cost | Approx. €0.20, operator-reported | No independent Cost Explorer export was attached. For a public numeric claim, preserve the range, currency, cost metric, project/account attribution, and credits/refunds treatment |
| Terraform validation | Pass | [Latest validation on the last Terraform-code commit](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358); later commits are documentation-only |
| Gitleaks | Pass | [Current-head Gitleaks run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39597613731) |
| Teardown | Not performed after latest redeployment | Keep or remove the app intentionally. If removing it, preserve the remote state and backup roots unless you have deliberately decided they are no longer needed |

The table above is the honest closeout record; it separates operator-confirmed live tests from evidence independently retrievable from GitHub. Exact recovery timing and exact total cost are optional deeper measurements, not blockers for labelling the portfolio project complete.

See [final-evidence.md](final-evidence.md) for the small recommended screenshot set.
