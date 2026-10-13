# IAM role assumed by EC2 container instances.
resource "aws_iam_role" "ecs_instance" {
  name = "uptimekuma-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "uptimekuma-ecs-instance-role"
  }
}

# Permissions required by the ECS container agent.
resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role = aws_iam_role.ecs_instance.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Allows administration through Systems Manager, without SSH.
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role = aws_iam_role.ecs_instance.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 requires an instance profile to receive this role.
resource "aws_iam_instance_profile" "ecs_instance" {
  name = "uptimekuma-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name

  tags = {
    Name = "uptimekuma-ecs-instance-profile"
  }
}

# IAM role assumed by the ECS task execution agent.
resource "aws_iam_role" "ecs_task_execution" {
  name = "uptimekuma-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "uptimekuma-ecs-task-execution-role"
  }
}

# Standard permissions for ECS task execution.
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role = aws_iam_role.ecs_task_execution.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
