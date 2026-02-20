output "alb_dns" {
  description = "ALB DNS — hit this to test the app: curl http://<alb_dns>/health"
  value       = aws_lb.main.dns_name
}

output "asg_name" {
  description = "Auto Scaling Group name (use to find instance IDs)"
  value       = aws_autoscaling_group.app.name
}

output "instance_type" {
  description = "Current instance type (WasteHunter will detect this as waste)"
  value       = var.instance_type
}

output "get_instance_ids" {
  description = "Command to list running instance IDs"
  value       = "aws ec2 describe-instances --filters Name=tag:WasteHunter,Values=monitor Name=instance-state-name,Values=running --query 'Reservations[*].Instances[*].InstanceId' --output text --region ${var.aws_region}"
}
