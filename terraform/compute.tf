# Use the latest ECS-optimized Amazon Linux 2023 AMI for this region.
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_launch_template" "ecs" {
  name_prefix   = "uptimekuma-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3.small"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance.name
  }

  vpc_security_group_ids = [
    aws_security_group.ecs_instances.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Restore the newest known-good app-data archive before ECS can start tasks.
    systemctl stop ecs || true
    DATA_DIR="/var/lib/uptimekuma"
    BACKUP_BUCKET="${local.backup_bucket_name}"
    RESTORE_DIR="$(mktemp -d)"
    trap 'rm -rf "$RESTORE_DIR"' EXIT
    mkdir -p "$DATA_DIR"

    LATEST_KEY="$(aws s3api list-objects-v2 \
      --bucket "$BACKUP_BUCKET" \
      --prefix "uptimekuma/archives/" \
      --query 'reverse(sort_by(Contents, &LastModified))[0].Key' \
      --output text \
      --region eu-west-1)"

    if [ -n "$LATEST_KEY" ] && [ "$LATEST_KEY" != "None" ]; then
      ARCHIVE="$RESTORE_DIR/uptimekuma-backup.tar.gz"
      CHECKSUM="$RESTORE_DIR/uptimekuma-backup.sha256"
      aws s3 cp "s3://$BACKUP_BUCKET/$LATEST_KEY" "$ARCHIVE" --region eu-west-1 --only-show-errors
      CHECKSUM_KEY="uptimekuma/checksums/$(basename "$LATEST_KEY").sha256"
      aws s3 cp "s3://$BACKUP_BUCKET/$CHECKSUM_KEY" "$CHECKSUM" --region eu-west-1 --only-show-errors

      EXPECTED_SHA="$(tr -d '[:space:]' < "$CHECKSUM")"
      ACTUAL_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
      if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
        echo "Backup checksum mismatch. Refusing to start ECS against unverified data." >&2
        exit 1
      fi

      mkdir "$RESTORE_DIR/extracted"
      tar -xzf "$ARCHIVE" -C "$RESTORE_DIR/extracted"
      RESTORED_DB="$RESTORE_DIR/extracted/data/kuma.db"
      if [ ! -f "$RESTORED_DB" ]; then
        echo "Backup archive does not contain data/kuma.db." >&2
        exit 1
      fi
      python3 -c 'import sqlite3,sys; p=sys.argv[1]; db=sqlite3.connect("file:"+p+"?mode=ro",uri=True); result=db.execute("PRAGMA integrity_check").fetchone()[0]; db.close(); print(result); sys.exit(0 if result == "ok" else 1)' "$RESTORED_DB"

      find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
      cp -a "$RESTORE_DIR/extracted/data/." "$DATA_DIR/"
      logger "Uptime Kuma data restored from verified backup: $LATEST_KEY"
    else
      logger "No application backup exists yet; starting with a fresh Uptime Kuma data directory."
    fi

    printf 'ECS_CLUSTER=%s\n' "${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
    systemctl enable ecs
    systemctl start ecs
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "uptimekuma-ecs-instance"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Name = "uptimekuma-ecs-volume"
    }
  }

  # Ensure the instance role has backup/restore permissions before ASG
  # launches an instance whose user data accesses the S3 backup bucket.
  depends_on = [aws_iam_role_policy.ecs_instance_backup]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "uptimekuma-ecs-launch-template"
  }
}
