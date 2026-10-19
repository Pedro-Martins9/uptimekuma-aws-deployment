# Portfolio evidence capture

Use this checklist during one deliberately time-boxed test deployment. The application stack is currently offline. This document prepares the evidence workflow; it does not mean another deployment or alarm test has run.

## Before deployment

- [ ] Agree the test window and acceptable spend before applying anything. Review the entire Terraform plan and confirm the target AWS account.
- [ ] Configure the existing remote-state bucket name in each backend block and set `TF_VAR_aws_account_id`. For GitHub Actions, configure `AWS_ACCOUNT_ID`, the role ARNs, `TFPLAN_ENCRYPTION_KEY`, `BUDGET_ALERT_EMAIL` and (if needed) `MONTHLY_BUDGET_LIMIT_USD`.
- [ ] Confirm the intended public exposure: the ALB accepts public IPv4 traffic on TCP 80/443, HTTP redirects to HTTPS, and ECS dynamic host-port ingress is limited to the ALB security group. Use strong, unique Uptime Kuma credentials because the login page will be internet-accessible.
- [ ] Before deployment, revisit ECS EC2 Docker bridge dynamic host-port mapping and verify the EC2 host ephemeral-port range against ALB egress and ECS instance ingress rules (currently TCP 32768–65535). A prior SSM check reported host range 32768–60999; do not treat that comparison as verified without checking the actual allocation and target mapping.
- [ ] The default dashboard hostname is `uptime.pedromartins9.me` (override using `TF_VAR_domain_name` locally or the `UPTIME_KUMA_DOMAIN_NAME` GitHub Actions repository variable). Verify that the ACM certificate is **ISSUED in `eu-west-1`** and that its primary domain or SAN covers this exact hostname. A certificate for `pedromartins9.me` alone does not cover the subdomain; a suitable wildcard or SAN certificate does. The Terraform root looks up the existing certificate and does not create a duplicate.
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
7. **HTTPS, if implemented:** validated ACM certificate, HTTPS listener and HTTP-to-HTTPS redirect.
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

## Final evidence summary template

| Item | Result |
|---|---|
| Tested commit | To be recorded |
| Deployment window (UTC) | To be recorded |
| ECS service / ALB health | To be recorded |
| Restore request-to-healthy-target duration | To be measured |
| Dashboard data restored | Pass/fail, with sanitized evidence |
| Backup checksum and database integrity | Exact evidence to be recorded |
| SNS email and OK transition | To be tested |
| HTTPS | Implemented / not implemented |
| Cost date range and metric | To be recorded from Cost Explorer |
| Reported cost and treatment of credits | To be recorded; no estimate |
| Teardown and post-destroy audit | To be recorded |

Only change a status to pass after collecting the evidence. The current project README must continue to describe the stack as offline until the next test deployment is explicitly completed.
