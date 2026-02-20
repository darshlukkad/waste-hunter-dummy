# ── WasteHunter Target Infrastructure ────────────────────────────────────────
# Deploys into an existing VPC using hardcoded IDs — no data sources needed.
# Requires an IAM user/role with: EC2, VPC, ALB, AutoScaling, IAM permissions.
#
# Quick start:
#   1. Copy terraform.tfvars.example → terraform.tfvars and fill in values
#   2. terraform init
#   3. terraform apply
#
# Estimated cost: ~$0.04/hr (t3.medium on-demand, us-west-2)
# WasteHunter will recommend: t3.medium → t3.micro (saves ~75%)
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── IAM: EC2 instance role ────────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "wastehunter-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "wastehunter-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── Security Groups ───────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name   = "wastehunter-alb-sg"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wastehunter-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name   = "wastehunter-ec2-sg"
  vpc_id = var.vpc_id
  ingress {
    description     = "App traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "wastehunter-ec2-sg" }
}

# ── Load Balancer ─────────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "wastehunter-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  tags               = { Name = "wastehunter-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "wastehunter-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  tags = { Name = "wastehunter-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── EC2 Launch Template ───────────────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "wastehunter-"
  image_id      = var.ami_id
  instance_type = var.instance_type   # ⚠️ WASTE TARGET — WasteHunter rewrites this line

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "wastehunter-rec-engine"
      Service     = "recommendation-engine"
      Environment = "test"
      Team        = "platform"
      ManagedBy   = "terraform"
      WasteHunter = "monitor"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    dd_api_key = var.datadog_api_key
    dd_site    = var.datadog_site
  }))
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                      = "wastehunter-asg"
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  health_check_grace_period = 180
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "wastehunter-rec-engine"
    propagate_at_launch = true
  }
}

# ── Auto Scaling Policies ─────────────────────────────────────────────────────
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "wastehunter-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 120
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "wastehunter-scale-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "wastehunter-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "wastehunter-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 10
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.app.name }
}
