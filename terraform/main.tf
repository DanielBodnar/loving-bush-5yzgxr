resource "aws_ecs_cluster" "interview_cluster" {
  name = "interview-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name                  = "interview-ecs-execution-role"
  path                  = "/service-role/"
  force_detach_policies = false

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  ]
  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ecs-tasks.amazonaws.com"
          }
          Sid = ""
        },
      ]
      Version = "2012-10-17"
    }
  )
}

data "aws_ecr_repository" "ecr_repository" {
  name = "interview_repo"
}

resource "aws_ecs_task_definition" "ecs_task_definition" {
  family = "interview-service-task-definition"
  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn = aws_iam_role.ecs_execution_role.arn

  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory = 512
  cpu = 256
  container_definitions = jsonencode([
    {
      name      = "test_app"
      image     = "${data.aws_ecr_repository.ecr_repository.repository_url}"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:5000 || exit 1"
        ]
        interval = 30
        timeout = 5
        retries = 3
      },
    }
  ])
}

resource "aws_ecs_service" "interview_service" {
  name = "interview_service"
  cluster = aws_ecs_cluster.interview_cluster.name
  desired_count = 1
  launch_type = "FARGATE"
  depends_on = [aws_iam_role.ecs_execution_role]

  task_definition = aws_ecs_task_definition.ecs_task_definition.arn

  load_balancer {
    target_group_arn = aws_lb_target_group.test_app_target_group.arn
    container_name = "test_app"
    container_port = 5000
  }

  network_configuration {
    subnets = [aws_subnet.subnet_01.id, aws_subnet.subnet_02.id]
    security_groups = [aws_security_group.load_balancer_security_group.id]
    assign_public_ip = true
  }
}

resource "aws_security_group" "load_balancer_security_group" {
  name        = "terraform_alb_security_group"
  description = "Terraform load balancer security group"
  vpc_id      = aws_vpc.test_server.id

  revoke_rules_on_delete = true

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "interview"
  }
}

