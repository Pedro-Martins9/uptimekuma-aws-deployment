resource "aws_ecs_cluster" "main" {
  name = "uptimekuma-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "uptimekuma-cluster"
  }
}
