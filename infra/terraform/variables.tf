variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
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
  default     = "datadoghq.com"   # change to us3.datadoghq.com / datadoghq.eu if needed
}
