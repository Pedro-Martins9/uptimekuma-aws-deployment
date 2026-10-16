# Uptime Kuma backup / restore drill

**Status: SUCCESSFUL RESTORE DEMONSTRATED — 16 October 2026; evidence record partially complete.** The operator manually ran the SSM backup, confirmed the archive and checksum sidecar were uploaded to S3, then replaced the EC2 instance through Auto Scaling. The replacement instance `i-02971a9f174fdf338` logged `Uptime Kuma data restored from verified backup: uptimekuma/archives/20261016T164644Z.tar.gz`. The dashboard screenshot shows the existing `wewatch` monitor and its history present and Up; the user also confirmed the target group was healthy. The startup script emits that log message only after checksum validation and SQLite `PRAGMA integrity_check` succeed. Direct digest and integrity-check output, the S3 object version ID, SSM execution ID, and exact first-healthy timestamp were not separately captured. The activity history and screenshot do support a bounded recovery-time estimate.

## Scope and recovery design

- Application data path on the EC2 host: `/var/lib/uptimekuma`.
- Uptime Kuma container path: `/app/data`.
- Persistent backup bucket: `REPLACE_WITH_APP_BACKUP_BUCKET` in `eu-west-1`.
- Archive keys: `uptimekuma/archives/<UTC timestamp>.tar.gz`.
- SHA-256 sidecar keys: `uptimekuma/checksums/<UTC timestamp>.tar.gz.sha256`.
- Scheduled backup: daily at 02:05 UTC through Systems Manager State Manager.
- Backup-freshness check: hourly; reports a fresh/not-fresh custom metric to CloudWatch.
- Restore mechanism: EC2 launch-template user data checks S3 for the newest archive, verifies the SHA-256 sidecar and SQLite integrity, restores app data, then starts the ECS agent.

The backup bucket and its Terraform state are kept separately from the application stack so application teardown should not delete recovery points.

## Prerequisites

1. The persistent Terraform state bucket already exists.
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
  --region eu-west-1 \
  --query "Associations[?AssociationName=='uptimekuma-daily-sqlite-backup'].AssociationId | [0]" \
  --output text)"

printf 'Association: %s\n' "$ASSOCIATION_ID"
test -n "$ASSOCIATION_ID" && test "$ASSOCIATION_ID" != "None"
```

Trigger it once rather than waiting for the daily schedule:

```bash
aws ssm start-associations-once \
  --association-ids "$ASSOCIATION_ID" \
  --region eu-west-1
```

Inspect the newest association execution and its target result:

```bash
aws ssm list-association-executions \
  --association-id "$ASSOCIATION_ID" \
  --region eu-west-1 \
  --max-results 5 \
  --output table

EXECUTION_ID="$(aws ssm list-association-executions \
  --association-id "$ASSOCIATION_ID" \
  --region eu-west-1 \
  --max-results 1 \
  --query 'AssociationExecutions[0].ExecutionId' \
  --output text)"

aws ssm describe-association-execution-targets \
  --association-id "$ASSOCIATION_ID" \
  --execution-id "$EXECUTION_ID" \
  --region eu-west-1 \
  --query 'AssociationExecutionTargets[].{Instance:ResourceId,Status:Status,Detail:DetailedStatus,Output:OutputSource}' \
  --output json
```

Wait until the most recent execution and target both report success. If the target fails, open Systems Manager → State Manager → the association → execution history to inspect the command output, then fix the cause before proceeding.

Verify that a new archive and checksum object exist:

```bash
aws s3api list-objects-v2 \
  --bucket REPLACE_WITH_APP_BACKUP_BUCKET \
  --prefix uptimekuma/archives/ \
  --region eu-west-1 \
  --query 'reverse(sort_by(Contents, &LastModified))[:5].[Key,LastModified,Size]' \
  --output table

aws s3api list-objects-v2 \
  --bucket REPLACE_WITH_APP_BACKUP_BUCKET \
  --prefix uptimekuma/checksums/ \
  --region eu-west-1 \
  --query 'reverse(sort_by(Contents, &LastModified))[:5].[Key,LastModified,Size]' \
  --output table
```

Record the exact archive key, checksum key, last-modified time and object version ID. Check that the archive's companion checksum object exists. Do not continue if this backup step has not succeeded.

## Force a replacement to exercise the real restore path

This test terminates the current test EC2 instance and lets the Auto Scaling Group replace it. It can briefly interrupt the test deployment. Run it only after the recovery point above has been verified and only against this project’s test instance.

```bash
INSTANCE_ID="$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names uptimekuma-ecs-asg \
  --region eu-west-1 \
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
  --region eu-west-1
```

Monitor the Auto Scaling Group and ECS service until the replacement is registered and the service returns to steady state:

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names uptimekuma-ecs-asg \
  --region eu-west-1 \
  --query 'AutoScalingGroups[].Instances[].{InstanceId:InstanceId,State:LifecycleState,Health:HealthStatus}' \
  --output table

aws ecs describe-services \
  --cluster uptimekuma-cluster \
  --services uptimekuma-service \
  --region eu-west-1 \
  --query 'services[].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount,Events:events[0:5].message}' \
  --output json
```

If the instance fails to register, use Systems Manager if it is online and inspect the cloud-init and ECS logs. Do not bypass checksum or database-integrity errors. A failed restore is a failed drill and must be fixed, not silently replaced with empty app data.

## Verify restored state

After the replacement task is healthy:

1. Open the Uptime Kuma dashboard through the ALB.
2. Confirm the exact `RESTORE-DRILL-CANARY` monitor exists and retains its configuration.
3. Confirm one or more pre-existing monitors and relevant settings are present.
4. Confirm the new EC2 instance's startup log includes `Uptime Kuma data restored from verified backup`.
5. Confirm the ECS target is healthy and the restored application is usable.
6. Collect the exact backup object key/version, SHA-256, deployment and restore timestamps, SSM execution ID, old/new EC2 IDs, target-health result, database integrity result, and sanitized screenshots/log extracts.

The startup restore routine runs `PRAGMA integrity_check` on the restored database and refuses to start ECS against an archive with a checksum mismatch or missing `kuma.db`.

## Record the result

Fill this in only after the drill:

| Field | Result |
|---|---|
| Date | 16 October 2026 |
| Backup archive key | `uptimekuma/archives/20261016T164644Z.tar.gz` |
| Checksum sidecar key | `uptimekuma/checksums/20261016T164644Z.tar.gz.sha256` |
| S3 object version ID | Not captured |
| SHA-256 | Operator confirmed archive/checksum matched; exact digest not recorded. Replacement startup logged `restored from verified backup`. |
| SSM backup execution ID | Not captured; manual association execution succeeded and uploaded archive + checksum |
| Previous EC2 instance | `i-0118b10e18ad8c2a0` |
| Replacement EC2 instance | `i-02971a9f174fdf338` |
| Replacement activity | Old instance terminated at `2026-10-16T16:48:24Z`; new instance launched in response and launch completed at `2026-10-16T16:48:31Z` |
| Restore log time | `2026-10-16 16:48:42Z` according to the replacement instance's journal |
| `PRAGMA integrity_check` | Startup progressed to the `restored from verified backup` log only after the integrity check passed; direct output `ok` was not captured |
| Uptime Kuma service healthy after replacement | **PASS** — user confirmed dashboard accessible and target group healthy |
| Existing application data | **PASS** — dashboard shows the previous `wewatch` monitor and its history |
| Named `RESTORE-DRILL-CANARY` monitor | Not created/checked; prior application monitor used as the restore marker |
| Backup timestamp to old-instance termination | Approximately 1 minute 40 seconds (`16:46:44Z` to `16:48:24Z`); this is a timestamp-to-termination gap, not an exact RPO measurement |
| Recovery-time bound | Dashboard screenshot file timestamp is `18:01:37` local time (`UTC+01:00`); replacement launched at `17:48:26` local time. Dashboard was working within **13 minutes 11 seconds** of the replacement launch; exact first-healthy time was not captured. |
| Evidence | Auto Scaling activity-history screenshot; Uptime Kuma dashboard screenshot; replacement-instance journal line pasted in the work log |
| Outcome | **SUCCESS — backup restore demonstrated end-to-end; some exact artifacts and timestamps still need recording** |

Target objectives for the first test, to measure rather than assume: RPO under 24 hours and RTO under 30 minutes.

## After the drill

**Teardown completed on 16 October 2026.** The operator applied a fresh destroy plan from the main application root after the ECS/Auto Scaling teardown initially stalled. After scaling the Auto Scaling Group's desired capacity to zero and replanning, Terraform reported **19 resources destroyed**. This removed the main application stack after the restore had been demonstrated.

Post-destroy checks still to confirm in the AWS Console:
1. The application ALB, ECS cluster/service, Auto Scaling Group, EC2 instance(s), and application CloudWatch log group are gone.
2. The persistent Terraform state bucket `REPLACE_WITH_EXISTING_TFSTATE_BUCKET` still exists.
3. The persistent backup bucket `REPLACE_WITH_APP_BACKUP_BUCKET` still exists and contains the archive and checksum from this test.
4. No orphaned EBS volume or other billable test resource remains.

Do not run destroy from `terraform/backup-infra/` or `terraform/bootstrap-state/`; those roots manage the persistent backup and state storage. The hourly and daily SSM associations were in the main application stack and were removed during teardown, so backup automation will not run while the app stack is offline.

A created archive and a successful checksum are not, by themselves, proof of recoverability. The proof from this test was the replacement instance restoring from the archive, the restoration log, and the previous `wewatch` monitor/history present after the application returned.
