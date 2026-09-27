# ONE generic module that deploys every service in the inventory.
# 3 services or 45: same code, just more entries in services.yaml.

locals {
  # Only services with a port get a target group + load balancer rule
  web_services = { for name, svc in var.services : name => svc if svc.port > 0 }
}

# ---------- Networking: who can reach the containers ----------
resource "aws_security_group" "tasks" {
  name        = "${var.name_prefix}-tasks"
  description = "Containers accept traffic only from the load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "this" {
  for_each          = var.services
  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = 3
}

# ---------- Task role: what YOUR code is allowed to do ----------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  for_each           = var.services
  name               = "${var.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "dynamodb" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:Query"]
    resources = [var.table_arn]
  }
}

resource "aws_iam_role_policy" "dynamodb" {
  for_each = { for name, svc in var.services : name => svc if svc.dynamodb_access }
  name     = "dynamodb-notes"
  role     = aws_iam_role.task[each.key].id
  policy   = data.aws_iam_policy_document.dynamodb.json
}

# ---------- Load balancer routing ----------
resource "aws_lb_target_group" "this" {
  for_each             = local.web_services
  name                 = "${var.name_prefix}-${each.key}" # max 32 characters
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip" # required for Fargate
  vpc_id               = var.vpc_id
  deregistration_delay = 10 # faster deploys/destroys for practice (default is 300s)

  health_check {
    path                = each.value.health_check_path
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener_rule" "this" {
  for_each     = local.web_services
  listener_arn = var.listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }
}

# ---------- The containers ----------
resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${var.repository_urls[each.key]}:${var.image_tag}"
    essential = true

    portMappings = each.value.port > 0 ? [{ containerPort = each.value.port, protocol = "tcp" }] : []

    environment = [
      for k, v in merge({ TABLE_NAME = var.table_name, AWS_REGION = var.region }, each.value.environment) :
      { name = k, value = v }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this[each.key].name
        awslogs-region        = var.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  for_each = var.services

  name            = each.key
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  # Only web services get attached to the load balancer
  dynamic "load_balancer" {
    for_each = each.value.port > 0 ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  # If a new version keeps crashing, ECS rolls back to the last working one
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.this]
}
