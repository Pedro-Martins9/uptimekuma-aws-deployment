resource "aws_ecs_service" "uptimekuma" {
  name            = "uptimekuma-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.uptimekuma.arn
  desired_count   = 1

  # Use the EC2 capacity provider configured for this cluster.
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 1
    base              = 0
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  health_check_grace_period_seconds = 120

  load_balancer {
    target_group_arn = aws_lb_target_group.uptimekuma.arn
    container_name   = "uptimekuma"
    container_port   = 3001
  }

  depends_on = [
    aws_lb_listener.http
  ]

  tags = {
    Name = "uptimekuma-service"
  }
}
