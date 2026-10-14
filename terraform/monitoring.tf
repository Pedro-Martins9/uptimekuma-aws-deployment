locals {
  alert_email_enabled = var.alert_email == null ? false : trimspace(var.alert_email) != ""
  alarm_actions       = local.alert_email_enabled ? [aws_sns_topic.alerts[0].arn] : []
}

resource "aws_sns_topic" "alerts" {
  count = local.alert_email_enabled ? 1 : 0

  name = "uptimekuma-alerts"

  tags = {
    Name = "uptimekuma-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = local.alert_email_enabled ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "uptimekuma-alb-unhealthy-targets"
  alarm_description   = "One or more Uptime Kuma ALB targets are unhealthy."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.uptimekuma.arn_suffix
  }

  tags = {
    Name = "uptimekuma-alb-unhealthy-targets"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_no_healthy_targets" {
  alarm_name          = "uptimekuma-alb-no-healthy-targets"
  alarm_description   = "The Uptime Kuma target group has fewer than one healthy target."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.uptimekuma.arn_suffix
  }

  tags = {
    Name = "uptimekuma-alb-no-healthy-targets"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  alarm_name          = "uptimekuma-ecs-no-running-task"
  alarm_description   = "Uptime Kuma has fewer than one running ECS task."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.uptimekuma.name
  }

  tags = {
    Name = "uptimekuma-ecs-no-running-task"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "uptimekuma-ecs-cpu-high"
  alarm_description   = "Uptime Kuma ECS service CPU utilisation exceeded 80 percent for five minutes."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.uptimekuma.name
  }

  tags = {
    Name = "uptimekuma-ecs-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "uptimekuma-ecs-memory-high"
  alarm_description   = "Uptime Kuma ECS service memory utilisation exceeded 80 percent for five minutes."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.uptimekuma.name
  }

  tags = {
    Name = "uptimekuma-ecs-memory-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  alarm_name          = "uptimekuma-alb-elb-5xx"
  alarm_description   = "The load balancer returned at least five 5xx responses in a five-minute period."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "uptimekuma-alb-elb-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "uptimekuma-alb-target-5xx"
  alarm_description   = "Uptime Kuma targets returned at least five 5xx responses in a five-minute period."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.uptimekuma.arn_suffix
  }

  tags = {
    Name = "uptimekuma-alb-target-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_no_in_service_instances" {
  alarm_name          = "uptimekuma-asg-no-in-service-instance"
  alarm_description   = "The Uptime Kuma Auto Scaling Group has no in-service EC2 instance for ten minutes."
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 10
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ecs.name
  }

  tags = {
    Name = "uptimekuma-asg-no-in-service-instance"
  }
}

resource "aws_cloudwatch_metric_alarm" "backup_stale_or_failed" {
  alarm_name          = "uptimekuma-backup-stale-or-failed"
  alarm_description   = "The hourly backup freshness check reports no recent S3 backup or has stopped reporting."
  namespace           = "UptimeKuma/Backup"
  metric_name         = "BackupFresh"
  statistic           = "Minimum"
  period              = 3600
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    Project = "uptimekuma"
  }

  tags = {
    Name = "uptimekuma-backup-stale-or-failed"
  }
}


resource "aws_cloudwatch_metric_alarm" "backup_execution_failed" {
  alarm_name          = "uptimekuma-backup-execution-failed"
  alarm_description   = "An SSM backup execution explicitly reported failure."
  namespace           = "UptimeKuma/Backup"
  metric_name         = "BackupSuccess"
  statistic           = "Minimum"
  period              = 3600
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    Project = "uptimekuma"
  }

  tags = {
    Name = "uptimekuma-backup-execution-failed"
  }
}
