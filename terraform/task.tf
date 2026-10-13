resource "aws_cloudwatch_log_group" "uptimekuma" {
  name              = "/ecs/uptimekuma"
  retention_in_days = 7

  tags = {
    Name = "uptimekuma-logs"
  }
}

resource "aws_ecs_task_definition" "uptimekuma" {
  family                   = "uptimekuma"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "uptimekuma"
      image     = "louislam/uptime-kuma:1"
      essential = true

      portMappings = [
        {
          containerPort = 3001
          hostPort      = 0
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "uptimekuma-data"
          containerPath = "/app/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.uptimekuma.name
          "awslogs-region"        = "eu-west-1"
          "awslogs-stream-prefix" = "uptimekuma"
        }
      }
    }
  ])

  volume {
    name      = "uptimekuma-data"
    host_path = "/var/lib/uptimekuma"
  }

  tags = {
    Name = "uptimekuma-task"
  }
}
