data "aws_caller_identity" "current" {}

locals {
  backup_bucket_name = format("uptimekuma-app-backups-%s", data.aws_caller_identity.current.account_id)
}

# A narrowly scoped EC2-instance policy is used by the daily SSM backup job
# and by launch-time restore. It cannot read or write outside this app prefix.
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
          "s3:ListBucketMultipartUploads",
        ]
        Resource = format("arn:aws:s3:::%s", local.backup_bucket_name)
        Condition = {
          StringLike = {
            "s3:prefix" = ["uptimekuma/*"]
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

# SSM State Manager executes this command on EC2 instances carrying Project=uptimekuma.
# SQLite's online backup API makes a consistent DB snapshot, including committed WAL data.
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
      set -eu
      BACKUP_BUCKET="${local.backup_bucket_name}"
      BACKUP_DIR="$(mktemp -d)"
      BACKUP_OK=0
      cleanup() {
        rm -rf "$BACKUP_DIR" || true
        if [ "$BACKUP_OK" -ne 1 ]; then
          aws cloudwatch put-metric-data --namespace UptimeKuma/Backup --metric-name BackupSuccess --value 0 --unit Count --dimensions Name=Project,Value=uptimekuma --region eu-west-1 || true
        fi
      }
      trap cleanup EXIT

      DATA_DB="/var/lib/uptimekuma/kuma.db"
      if [ ! -f "$DATA_DB" ]; then
        echo "Uptime Kuma database not found at $DATA_DB" >&2
        exit 1
      fi

      BACKUP_FILE="$BACKUP_DIR/kuma.db"
      python3 - "$DATA_DB" "$BACKUP_FILE" <<'PY'
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
      OBJECT_KEY="uptimekuma/$STAMP/kuma.db"
      aws s3 cp "$BACKUP_FILE" "s3://$BACKUP_BUCKET/$OBJECT_KEY" --sse AES256 --region eu-west-1 --only-show-errors
      aws s3api head-object --bucket "$BACKUP_BUCKET" --key "$OBJECT_KEY" --region eu-west-1 >/dev/null
      aws cloudwatch put-metric-data --namespace UptimeKuma/Backup --metric-name BackupSuccess --value 1 --unit Count --dimensions Name=Project,Value=uptimekuma --region eu-west-1
      BACKUP_OK=1
      echo "Backup succeeded: s3://$BACKUP_BUCKET/$OBJECT_KEY"
    EOT
  }
}
