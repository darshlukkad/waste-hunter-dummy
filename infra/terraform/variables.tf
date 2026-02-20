variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "vpc_id" {
  description = "ID of an existing VPC to deploy into. Use the default VPC from your AWS Console → VPC → Your VPCs."
  type        = string
  # Find yours: AWS Console → VPC → Your VPCs → copy the default VPC ID
  # e.g. "vpc-0c3b19d3a75cd8d1a"
}

variable "subnet_ids" {
  description = "List of subnet IDs in the VPC (needs at least 2 AZs for ALB)."
  type        = list(string)
  # Find yours: AWS Console → VPC → Subnets → filter by vpc_id → copy 2+ subnet IDs
  # e.g. ["subnet-0abc123", "subnet-0def456"]
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID for the region."
  type        = string
  # Find yours: AWS Console → EC2 → AMI Catalog → search 'al2023' → copy ID for your region
  default     = "ami-05572e392e45e5900"   # AL2023, us-west-2, Feb 2025
}

variable "instance_type" {
  description = "EC2 instance type. Intentionally oversized — WasteHunter will recommend downsizing."
  type        = string
  default     = "t3.medium"   # actual app uses ~2% CPU → WasteHunter recommends t3.micro
}

variable "datadog_api_key" {
  description = "Datadog API key — installed on EC2 agent"
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog intake site"
  type        = string
  default     = "datadoghq.com"
}
