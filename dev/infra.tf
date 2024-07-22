provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region"
  default     = "us-east-1"
}

variable "environment" {
  description = "The environment (e.g., dev, prod)"
  default     = "dev"
}

variable "db_password" {
  description = "The password for the RDS instance"
  type        = string
  sensitive   = true
}

# Define the VPC
resource "aws_vpc" "main" {
  cidr_block = "100.0.0.0/16"
  tags = {
    Name = "kapersky-${var.region}-${var.environment}-vpc"
  }
}

# Define public subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = true

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-public-subnet-${count.index + 1}"
  }
}

# Define private subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = false

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-private-subnet-${count.index + 1}"
  }
}

# Define Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-igw"
  }
}

# Define NAT Gateway
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.gw]
  vpc        = true

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-eip-nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-nat"
  }
}

# Define route tables for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public_association" {
  count          = 2
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Define route tables for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private_association" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

# Data source to get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-alb-sg"
  }
}

# Web Server Security Group
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-web-sg"
  }
}

# RDS Security Group
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["100.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-rds-sg"
  }
}

# ALB
resource "aws_lb" "main" {
  name               = "kapersky-${var.region}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-alb"
  }
}

# ALB Target Group
resource "aws_lb_target_group" "main" {
  name     = "kapersky-${var.region}-${var.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Launch EC2 instances
resource "aws_instance" "web" {
  count         = 2
  ami           = "ami-04a81a99f5ec58529" # Ubuntu Server 20.04 LTS (HVM), SSD Volume Type - us-east-1
  instance_type = "t2.micro"
  subnet_id     = element(aws_subnet.public.*.id, count.index)


  tags = {
    Name = "kapersky-${var.region}-${var.environment}-web-${count.index + 1}"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg-agent \
                software-properties-common
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              add-apt-repository \
                "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) \
                stable"
              apt-get update
              apt-get install -y docker-ce docker-ce-cli containerd.io
              systemctl start docker
              systemctl enable docker
            EOF
}

#Register instances with ALB Target Group
resource "aws_lb_target_group_attachment" "web" {
  count            = 2
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = element(aws_instance.web.*.id, count.index)
  port             = 80
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "kapersky-${var.region}-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-db-subnet-group"
  }
}

# RDS MySQL instance
resource "aws_db_instance" "mysql" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name                 = "mydb"
  username             = "admin"
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.main.name

  tags = {
    Name = "kapersky-${var.region}-${var.environment}-rds"
  }
}

