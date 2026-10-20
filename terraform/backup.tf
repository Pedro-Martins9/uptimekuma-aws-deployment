data "aws_caller_identity" "current" {}

locals {
  backup_bucket_name = format("uptimekuma-app-backups-%s", data.aws_caller_identity.current.account_id)
}

# Least-privilege access for the EC2 instance to back up and restore only this app prefix.
resource "aws_iam_role_policy" "ecs_instance_backup" {
  name = "uptimekuma-instance-backup"
  role = aws_iam_role.ecs_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = format("arn:aws:s3:::%s/uptimekuma/*", local.backup_bucket_name)
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = format("arn:aws:s3:::%s", local.backup_bucket_name)
        Condition = {
          StringLike = {
            "s3:prefix" = ["uptimekuma/archives/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "UptimeKuma/Backup"
          }
        }
      }
    ]
  })
}

# SSM State Manager takes a transactionally consistent SQLite snapshot, then
# packages the rest of the app data directory alongside it.
resource "aws_ssm_association" "daily_backup" {
  name                        = "AWS-RunShellScript"
  association_name            = "uptimekuma-daily-sqlite-backup"
  schedule_expression         = "cron(5 2 * * ? *)"
  apply_only_at_cron_interval = true
  max_concurrency             = "1"
  max_errors                  = "1"

  targets {
    key    = "tag:Project"
    values = ["uptimekuma"]
  }

  parameters = {
    commands = <<-EOT
      set -euo pipefail
      BACKUP_BUCKET="${local.backup_bucket_name}"
      DATA_DIR="/var/lib/uptimekuma"
      BACKUP_DIR="$(mktemp -d)"
      BACKUP_OK=0
      cleanup() {
        rm -rf "$BACKUP_DIR" || true
        if [ "$BACKUP_OK" -ne 1 ]; then
          aws cloudwatch put-metric-data --namespace UptimeKuma/Backup --metric-name BackupSuccess --value 0 --unit Count --dimensions Project=uptimekuma --region eu-west-1 || true
        fi
      }
      trap cleanup EXIT

      DATA_DB="$DATA_DIR/kuma.db"
      if [ ! -f "$DATA_DB" ]; then
        echo "Uptime Kuma database not found at $DATA_DB" >&2
        exit 1
      fi

      mkdir -p "$BACKUP_DIR/data"
      tar --exclude='./kuma.db*' -C "$DATA_DIR" -cf - . | tar -C "$BACKUP_DIR/data" -xf -
      python3 - "$DATA_DB" "$BACKUP_DIR/data/kuma.db" <<'PY'
      import sqlite3
      import sys

      source_path, backup_path = sys.argv[1], sys.argv[2]
      source = sqlite3.connect("file:" + source_path + "?mode=ro", uri=True)
      destination = sqlite3.connect(backup_path)
      try:
          source.backup(destination)
          result = destination.execute("PRAGMA integrity_check").fetchone()[0]
          if result != "ok":
              raise RuntimeError("SQLite integrity check failed: " + str(result))
          destination.commit()
      finally:
          destination.close()
          source.close()
      print("SQLite snapshot created and integrity-checked")
      PY

      STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
      ARCHIVE="$BACKUP_DIR/uptimekuma-backup.tar.gz"
      OBJECT_KEY="uptimekuma/archives/$STAMP.tar.gz"
      CHECKSUM_KEY="uptimekuma/checksums/$STAMP.tar.gz.sha256"
      tar -czf "$ARCHIVE" -C "$BACKUP_DIR" data
      SHA256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
      printf '%s\n' "$SHA256" > "$BACKUP_DIR/uptimekuma-backup.sha256"

      aws s3 cp "$ARCHIVE" "s3://$BACKUP_BUCKET/$OBJECT_KEY" --sse AES256 --region eu-west-1 --only-show-errors
      aws s3 cp "$BACKUP_DIR/uptimekuma-backup.sha256" "s3://$BACKUP_BUCKET/$CHECKSUM_KEY" --sse AES256 --region eu-west-1 --only-show-errors
      aws s3api head-object --bucket "$BACKUP_BUCKET" --key "$OBJECT_KEY" --region eu-west-1 >/dev/null
      aws cloudwatch put-metric-data --namespace UptimeKuma/Backup --metric-name BackupSuccess --value 1 --unit Count --dimensions Project=uptimekuma --region eu-west-1
      BACKUP_OK=1
      echo "Backup succeeded: s3://$BACKUP_BUCKET/$OBJECT_KEY"
    EOT
  }
}


# Periodically publish whether the newest S3 backup is fresh. This emits a
# data point every hour so CloudWatch can detect both stale data and a missing
# freshness check, instead of treating a once-daily datapoint as a heartbeat.
resource "aws_ssm_association" "backup_freshness" {
  name                        = "AWS-RunShellScript"
  association_name            = "uptimekuma-backup-freshness-check"
  schedule_expression         = "cron(0 0/1 * * ? *)"
  apply_only_at_cron_interval = true
  max_concurrency             = "1"
  max_errors                  = "1"

  targets {
    key    = "tag:Project"
    values = ["uptimekuma"]
  }

  parameters = {
    commands = <<-EOT
      set -eu
      BACKUP_BUCKET="${local.backup_bucket_name}"
      LAST_MODIFIED="$(aws s3api list-objects-v2 --bucket "$BACKUP_BUCKET" --prefix "uptimekuma/archives/" --query 'reverse(sort_by(Contents || `[]`, &LastModified))[0].LastModified' --output text --region eu-west-1)"
      FRESH=0
      if [ -n "$LAST_MODIFIED" ] && [ "$LAST_MODIFIED" != "None" ]; then
        LAST_EPOCH="$(date -d "$LAST_MODIFIED" +%s)"
        NOW_EPOCH="$(date +%s)"
        AGE_SECONDS="$((NOW_EPOCH - LAST_EPOCH))"
        if [ "$AGE_SECONDS" -ge 0 ] && [ "$AGE_SECONDS" -le 93600 ]; then
          FRESH=1
        fi
      fi
      aws cloudwatch put-metric-data --namespace UptimeKuma/Backup --metric-name BackupFresh --value "$FRESH" --unit Count --dimensions Project=uptimekuma --region eu-west-1
      echo "BackupFresh=$FRESH; S3 LastModified=$LAST_MODIFIED"
    EOT
  }
}
