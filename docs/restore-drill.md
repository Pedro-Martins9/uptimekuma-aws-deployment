# Uptime Kuma backup / restore drill

**Status: SUCCESSFUL RESTORE DEMONSTRATED — 16 October 2026; evidence record partially complete.** A manual Systems Manager backup uploaded an archive and SHA-256 sidecar to S3. Auto Scaling replaced the test EC2 instance, and the replacement's startup log reported restoration from a verified, timestamped archive. The Uptime Kuma dashboard was subsequently accessible with previously configured monitor data and history present; the load balancer target was healthy. The startup path emits the restore-success log only after checksum validation and SQLite `PRAGMA integrity_check` succeed. Direct checksum/integrity output, the S3 object version ID, SSM execution ID, and exact first-healthy timestamp were not separately captured. The evidence supports a bounded recovery-time observation, not an exact RTO or RPO measurement.

## Scope and recovery design

- Application data path on the EC2 host: `/var/lib/uptimekuma`.
- Uptime Kuma container path: `/app/data`.
- AWS region used during the test: `eu-west-1`.
- Persistent backup bucket: `<APP_BACKUP_BUCKET>` (replace with the bucket configured in your own environment when following the commands).
- Archive keys: `uptimekuma/archives/<UTC timestamp>.tar.gz`.
- SHA-256 sidecar keys: `uptimekuma/checksums/<UTC timestamp>.tar.gz.sha256`.
- Scheduled backup: daily at 02:05 UTC through Systems Manager State Manager while the application stack is deployed.
- Backup-freshness check: hourly; reports a fresh/not-fresh custom metric to CloudWatch while the application stack is deployed.
- Restore mechanism: EC2 launch-template user data checks S3 for the newest archive, verifies the SHA-256 sidecar and SQLite integrity, restores app data, then starts the ECS agent.

The backup bucket and its Terraform state are managed separately from the application stack. Application teardown should not delete recovery points or Terraform state.

## Prerequisites

1. The persistent Terraform state bucket already exists and the backend is configured to point to it.
2. Apply `terraform/backup-infra/` and verify its output before deploying the application stack.
3. Deploy the main stack from `terraform/`.
4. Confirm the EC2 instance is online in Systems Manager and the ECS service is healthy.
5. Have permission to access Uptime Kuma and create a temporary, clearly named test monitor. Use a harmless endpoint you control.
6. Set up an email recipient for CloudWatch alarms, confirm the SNS subscription, and keep the test deployment time-boxed to control cost.

Do not test with a production service or data that you cannot afford to lose.

## Create a known recovery point

Create a monitor named `RESTORE-DRILL-CANARY` in Uptime Kuma and note its exact name and target. This is a test marker that should appear after restoration.

Find the daily backup association:

```bash
ASSOCIATION_ID="$(aws ssm list-associations \
  --region <AWS_REGION> \
  --query "Associations[?AssociationName=='uptimekuma-daily-sqlite-backup'].AssociationId | [0]" \
  --output text)"

printf 'Association: %s\n' "$ASSOCIATION_ID"
test -n "$ASSOCIATION_ID" && test "$ASSOCIATION_ID" != "None"
```

Trigger it once rather than waiting for the daily schedule:

```bash
aws ssm start-associations-once \
  --association-ids "$ASSOCIATION_ID" \
  --region <AWS_REGION>
```

Inspect the newest association execution and its target result:

```bash
aws ssm list-association-executions \
  --association-id "$ASSOCIATION_ID" \
  --region <AWS_REGION> \
  --max-results 5 \
  --output table

EXECUTION_ID="$(aws ssm list-association-executions \
  --association-id "$ASSOCIATION_ID" \
  --region <AWS_REGION> \
  --max-results 1 \
  --query 'AssociationExecutions[0].ExecutionId' \
  --output text)"

aws ssm describe-association-execution-targets \
  --association-id "$ASSOCIATION_ID" \
  --execution-id "$EXECUTION_ID" \
  --region <AWS_REGION> \
  --query 'AssociationExecutionTargets[].{Instance:ResourceId,Status:Status,Detail:DetailedStatus,Output:OutputSource}' \
  --output json
```

Wait until the most recent execution and target both report success. If the target fails, open Systems Manager → State Manager → the association → execution history to inspect the command output, then fix the cause before proceeding.

Verify that a new archive and checksum object exist (replace `<APP_BACKUP_BUCKET>` first):

```bash
aws s3api list-objects-v2 \
  --bucket <APP_BACKUP_BUCKET> \
  --prefix uptimekuma/archives/ \
  --region <AWS_REGION> \
  --query 'reverse(sort_by(Contents, &LastModified))[:5].[Key,LastModified,Size]' \
  --output table

aws s3api list-objects-v2 \
  --bucket <APP_BACKUP_BUCKET> \
  --prefix uptimekuma/checksums/ \
  --region <AWS_REGION> \
  --query 'reverse(sort_by(Contents, &LastModified))[:5].[Key,LastModified,Size]' \
  --output table
```

Record the exact archive key, checksum key, last-modified time and object version ID. Check that the archive's companion checksum object exists. Do not continue if this backup step has not succeeded.

## Force a replacement to exercise the real restore path

This test terminates the current test EC2 instance and lets the Auto Scaling Group replace it. It can briefly interrupt the test deployment. Run it only after the recovery point above has been verified and only against this project's test instance.

First verify that the ASG and instance belong to this project. Replace `<ASG_NAME>` with the actual Auto Scaling Group name from your Terraform outputs or AWS Console:

```bash
INSTANCE_ID="$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <ASG_NAME> \
  --region <AWS_REGION> \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId | [0]' \
  --output text)"

printf 'Instance to replace: %s\n' "$INSTANCE_ID"
test -n "$INSTANCE_ID" && test "$INSTANCE_ID" != "None"
```

Verify the ID before continuing. Then request an instance replacement while retaining the ASG desired capacity:

```bash
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id "$INSTANCE_ID" \
  --no-should-decrement-desired-capacity \
  --region <AWS_REGION>
```

Monitor the Auto Scaling Group and ECS service until the replacement is registered and the service returns to steady state (replace the cluster and service placeholders first):

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names <ASG_NAME> \
  --region <AWS_REGION> \
  --query 'AutoScalingGroups[].Instances[].{InstanceId:InstanceId,State:LifecycleState,Health:HealthStatus}' \
  --output table

aws ecs describe-services \
  --cluster <ECS_CLUSTER_NAME> \
  --services <ECS_SERVICE_NAME> \
  --region <AWS_REGION> \
  --query 'services[].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount,Events:events[0:5].message}' \
  --output json
```

If the instance fails to register, use Systems Manager if it is online and inspect cloud-init and ECS logs. Do not bypass checksum or database-integrity errors. A failed restore is a failed drill and must be fixed, not silently replaced with empty app data.

## Verify restored state

After the replacement task is healthy:

1. Open the Uptime Kuma dashboard through the ALB.
2. Confirm the exact temporary canary monitor exists and retains its configuration.
3. Confirm one or more pre-existing monitors and relevant settings are present.
4. Confirm the new EC2 instance's startup log includes the verified-backup restore message.
5. Confirm the ECS target is healthy and the restored application is usable.
6. Collect the backup object key/version, SHA-256, deployment and restore timestamps, SSM execution ID, old/new EC2 IDs, target-health result, database integrity result, and sanitized screenshots/log extracts.

The startup restore routine runs `PRAGMA integrity_check` on the restored database and refuses to start ECS against an archive with a checksum mismatch or missing `kuma.db`.

## Record the result

Fill this in only after the drill:

| Field | Result |
|---|---|
| Date | 16 October 2026 |
| Backup archive key | `uptimekuma/archives/<timestamp>.tar.gz` (exact key retained in private operator notes) |
| Checksum sidecar key | `uptimekuma/checksums/<timestamp>.tar.gz.sha256` |
| S3 object version ID | Not captured |
| SHA-256 | Operator confirmed archive/checksum matched; exact digest not recorded. Replacement startup logged restoration from a verified backup. |
| SSM backup execution ID | Not captured; manual association execution succeeded and uploaded archive + checksum |
| Previous/replacement EC2 instances | Identifiers omitted from this publication copy; available in private operator evidence |
| Replacement activity | Old instance terminated shortly after backup; exact events retained in private operator evidence |
| Restore log time | Restore-success log recorded shortly after replacement launch; exact timestamp omitted here |
| `PRAGMA integrity_check` | Startup progressed to the verified-backup restore log only after integrity validation; direct `ok` output was not captured |
| Uptime Kuma service healthy after replacement | **PASS** — dashboard accessible and load-balancer target healthy |
| Existing application data | **PASS** — previous monitor configuration and history were present |
| Named canary monitor | Not created/checked; prior application data was used as the restore marker |
| Recovery-time bound | Dashboard was working within approximately 13 minutes 11 seconds of replacement launch, based on available timestamps. This is an upper bound, not an exact RTO. |
| Evidence | Auto Scaling activity-history screenshot; dashboard screenshot; replacement-instance journal message in private operator notes |
| Outcome | **SUCCESS — backup restore demonstrated end-to-end; exact artifacts/timestamps remain incomplete** |

Initial targets for a future measured drill (not claims about this test): RPO under 24 hours and RTO under 30 minutes.

## After the drill

**Teardown completed on 16 October 2026.** After the ECS/Auto Scaling teardown initially stalled, a fresh destroy plan was applied from the main application root. Scaling the Auto Scaling Group's desired capacity to zero and replanning allowed Terraform to report **19 resources destroyed**. The application stack was removed after the restore demonstration.

**Post-destroy audit completed:** the operator confirmed the application resources were removed, no leftover application resources were found, and the separate Terraform state and application-backup S3 buckets remain. Those buckets may continue to incur small storage charges. The app stack's daily backup and hourly freshness SSM associations were removed with the application stack, so scheduled backups are not running while it is offline.

Do not run destroy from `terraform/backup-infra/` or `terraform/bootstrap-state/`; those roots manage persistent backup and state storage. Retain the state bucket while the remote states depend on it. Before eventually deleting persistent storage, plan and review that operation separately.

The recoverability proof was the replacement instance restoring from the archive, the startup restore-success log, the previous monitor data/history present after the application returned, and the healthy load-balancer target. A created archive and checksum alone would not prove recovery.
