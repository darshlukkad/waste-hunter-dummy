# ── MOCK Terraform — prod-api-server-03 ───────────────────────────────────────
# This is the target IaC file that the MiniMax agent (Phase 3) will rewrite
# to downsize i-0a1b2c3d4e5f67890 from m5.4xlarge → m5.xlarge.
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
  region = "us-east-1"
}

# ── EC2 Instance (WASTE TARGET) ───────────────────────────────────────────────
resource "aws_instance" "prod_api_server_03" {
  ami           = "ami-0c02fb55956c7d316"   # Amazon Linux 2
  instance_type = "m5.4xlarge"              # ⚠️  WASTE: 16 vCPU / 64 GB, avg CPU 3.2%

  tags = {
    Name        = "prod-api-server-03"
    Environment = "production"
    Service     = "recommendation-engine"
    CostCenter  = "eng-platform"
    Owner       = "alice@company.com"
    ManagedBy   = "terraform"
  }
}

# ── Supporting resources (blast radius context for Neo4j) ────────────────────
resource "aws_security_group" "api_sg" {
  name        = "prod-api-server-03-sg"
  description = "Security group for prod-api-server-03"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "recommendation_db" {
  identifier        = "recommendation-db"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  db_name           = "recommendations"
  username          = "dbadmin"
  password          = var.db_password

  tags = {
    ConnectedTo = "prod-api-server-03"   # Neo4j picks this up as a dependency edge
    Environment = "production"
  }
}

variable "db_password" {
  type      = string
  sensitive = true
}
