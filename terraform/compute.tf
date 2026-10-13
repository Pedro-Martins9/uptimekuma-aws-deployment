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
    echo "ECS_CLUSTER=${aws_ecs_cluster.main.name}" >> /etc/ecs/ecs.config
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

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "uptimekuma-ecs-launch-template"
  }
}
