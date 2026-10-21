# Final portfolio evidence pack

**Closeout date:** 21 October 2026  
**Purpose:** finish the portfolio presentation without another deployment or unnecessary live tests.

The operator confirms that S3 backups and alarm email notifications have already been tested successfully. Treat those functional tests as complete. This pack describes the evidence worth keeping; it does not require repeating successful tests solely for screenshots.

## 1. Existing evidence — link these, do not recreate them

| Claim | Evidence |
|---|---|
| Terraform application deployment succeeded | [Deployment run #20](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39461906090) |
| SNS topic/subscription and alarm wiring were deployed | [Deployment run #21](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39465845112) |
| Backup metric fix was deployed successfully | [Deployment run #22](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39473186374) |
| Terraform formatting and validation passed | [Terraform validation run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/runs/39472903358) |
| Secret scanning | [Gitleaks workflow and latest run](https://github.com/Pedro-Martins9/uptimekuma-aws-deployment/actions/workflows/gitleaks.yml) |
| Recovery after EC2 replacement was demonstrated | [Restore-drill record](restore-drill.md) |
| Architecture, setup and limitations are documented | [README](../README.md), [OIDC setup](oidc-setup.md) |

The workflow and restore-drill links are durable public evidence. Do not paste account-specific Terraform output, state contents, ARNs, instance IDs or private monitor URLs into public documentation.

## 2. Demo video and screenshot pack

A 2–3 minute screen recording is the highest-impact remaining presentation improvement. Show the dashboard and healthy ALB target, explain the infrastructure and OIDC plan/apply flow briefly, then use the existing restore-drill evidence to narrate replacement and recovery; finish with a sanitized alarm email. Do not perform another destructive recovery drill or trigger successful alarm tests solely to film the video. If the live stack is no longer available, make a narrated walkthrough using existing sanitized screenshots and logs instead.

## 2. Small screenshot pack

Capture these only if the screenshots are useful for a portfolio README, CV, or interview. Use the existing deployment; do not run another Terraform apply merely to produce them.

1. **Live application and HTTPS.** Browser address bar shows the HTTPS hostname and certificate-valid page, with the dashboard visible. Keep monitor URLs, tokens and private endpoint names out of the image.
2. **Runtime health.** ECS service showing desired/running task count and the ALB target group showing the task healthy. Crop out account IDs and unrelated resources.
3. **Backup and restore.** Existing restore-success log showing that the replacement instance restored data, plus a read-only S3 listing or object-properties view showing a recent archive and its matching checksum sidecar. Bucket names and account identifiers must be redacted. Because backup/restore was already tested, this is evidence capture, not a new drill.
4. **Alarm notification.** One alarm email and the corresponding CloudWatch alarm history, including the recovery/OK transition. Redact email addresses, account IDs and any private monitor information. The operator confirms the alarm-email tests have already passed; do not trigger them again just for the screenshot.
5. **Cost and budget.** Cost Explorer showing the chosen date range and actual cost, plus the budget's amount and alert thresholds. Hide billing identifiers and unrelated spend details.

If the portfolio should stay very lean, items 1–4 are the useful engineering proof; item 5 is only needed if you intend to publish a cost claim.

## 3. How to report the cost

The README deliberately omits the unverified cost estimate. Only publish a measured cost after recording the date range, currency, selected cost metric, credits/refunds treatment, and whether the figure is project-attributed or account-wide.

Budgets are thresholds, not evidence that the threshold amount was spent. Record whether each notification is based on **actual** or **forecasted** cost. A forecast alert can occur while actual spend is lower, and AWS notes that Budgets updates can lag resource usage. Do not describe a €10 configured threshold as €10 spent unless the billing data supports that.

Official references: [AWS Budgets — create a cost budget](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html), [AWS Budgets — managing costs](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html), [AWS Cost Explorer overview](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html).

## 4. Closeout decision

- [x] Application stack was deployed successfully in the recorded workflow.
- [x] Backup and recovery path was exercised; restore results are documented with measurement limitations.
- [x] Operator confirms S3 backups are working.
- [x] Operator confirms alert email tests, including recovery notifications, are working.
- [x] The current dynamic host-port path is marked operationally verified in the handoff.
- [x] Budgets are configured, according to the operator.
- [x] Gitleaks passed on the current closeout commit.
- [ ] Capture and publish a small set of sanitized screenshots if they materially improve the portfolio page. No redeployment or repeat backup/alarm test is needed solely for screenshots.
- [ ] Decide whether to retain the live stack for a scheduled demo window or perform a controlled application-root teardown. If tearing down, preserve the separate state/backup storage roots and audit remaining billable resources.

**Definition of finished:** the public repo explains the design and its limits, the links above substantiate CI/deployment/recovery work, operator-confirmed backup and notification tests are recorded accurately, and the cost statement is qualified. Exact RPO/RTO and a fully attributed cost report are optional enhancements, not blockers.