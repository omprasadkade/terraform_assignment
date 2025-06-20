provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# ========== SECURITY GROUPS ==========

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from anywhere (for test only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP access to reverse proxy"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from bastion only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  ingress {
    description = "HTTPS access to reverse proxy"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from bastion only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Limit to internal VPC range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ========== PRIVATE EC2 (NGINX) ==========

resource "aws_instance" "nginx_private" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = var.private_subnet
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1
              set -x
              apt-get update
              apt-get install -y nginx
              echo "<h1>Welcome from Private NGINX</h1>" > /var/www/html/index.html
              systemctl enable nginx
              systemctl start nginx
              EOF

  tags = {
    Name = "private-nginx"
  }
}

# ========== PUBLIC EC2 (BASTION) ==========

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = var.public_subnet
  key_name                    = var.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  depends_on                  = [aws_instance.nginx_private]

  user_data = <<-EOF
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1
              set -x
              apt-get update
              apt-get install -y nginx curl

              PRIVATE_IP="${aws_instance.nginx_private.private_ip}"

              for i in {1..10}; do
                if curl -s --connect-timeout 2 http://$PRIVATE_IP > /dev/null; then
                  echo "Private instance is up"
                  break
                fi
                echo "Waiting for private EC2 at $PRIVATE_IP..."
                sleep 5
              done

              cat <<NGINX_CONF > /etc/nginx/sites-available/proxy
              server {
                  listen 80;
                  location / {
                      proxy_pass http://$PRIVATE_IP;
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                      access_log /var/log/nginx/access.log;
                      error_log /var/log/nginx/error.log;
                  }
              }
              NGINX_CONF

              ln -sf /etc/nginx/sites-available/proxy /etc/nginx/sites-enabled/proxy
              rm -f /etc/nginx/sites-enabled/default
              nginx -t && systemctl restart nginx
              EOF

  tags = {
    Name = "bastion-reverse-proxy"
  }
}
