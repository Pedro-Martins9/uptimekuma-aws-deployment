
resource "aws_autoscaling_group" "ecs" {
  # Subnet references do not imply that public routing must exist first.
  # This hidden dependency also drains the ASG before Terraform removes the
  # route/associations and internet gateway during destroy.
  depends_on = [
    aws_route.public_internet,
    aws_route_table_association.public,
    aws_route_table_association.public_secondary,
  ]

  name                = "uptimekuma-ecs-asg"
  min_size            = 0
  desired_capacity    = 0
  max_size            = 1
  enabled_metrics     = ["GroupInServiceInstances"]
  metrics_granularity = "1Minute"
  vpc_zone_identifier = [
    aws_subnet.public.id,
    aws_subnet.public_secondary.id
  ]

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "uptimekuma-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = "uptimekuma"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [
      desired_capacity,
      tag,
    ]
  }
}

resource "aws_ecs_capacity_provider" "main" {
  name = "uptimekuma-ecs-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"

    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 100
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 1
      instance_warmup_period    = 300
    }
  }

  tags = {
    Name = "uptimekuma-ecs-capacity-provider"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = [
    aws_ecs_capacity_provider.main.name
  ]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 1
    base              = 0
  }
}

