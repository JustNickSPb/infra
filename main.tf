provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "ubuntu" {
  owners      = ["099720109477"]
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

data "aws_availability_zones" "available" {}

resource "aws_security_group" "app_server" {
  name = "My Security Group"

  dynamic "ingress" {
    for_each = ["80", "22", "81"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Создаем балансировщик
resource "aws_elb" "balancer" {
  name = "My-Balancer"

  availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  security_groups = [aws_security_group.app_server.id]

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = 80
    instance_protocol = "http"
  }
}

resource "aws_default_subnet" "availability_zone_1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "availability_zone_2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}

# Направляем на балансировщик наш домен
resource "aws_route53_zone" "primary" {
  name = "nickops.space"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "nickops.space"
  type    = "A"

  alias {
    name = aws_elb.balancer.dns_name
    zone_id = aws_elb.balancer.zone_id
    evaluate_target_health = true
  }
}


resource "aws_launch_configuration" "app_server" {
  name_prefix     = "App-"
  image_id        = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.app_server.id]
  key_name = "laptop"
  
  lifecycle {
    create_before_destroy = true
  }
}

# Отдаем инстанс на милость балансировщика
resource "aws_autoscaling_group" "app" {
  name = "ASG-${aws_launch_configuration.app_server.name}"
  launch_configuration = aws_launch_configuration.app_server.name
  min_size = 0
  max_size = 1
  #min_elb_capacity = 1
  vpc_zone_identifier  = [aws_default_subnet.availability_zone_1.id, aws_default_subnet.availability_zone_2.id]
  load_balancers = [aws_elb.balancer.name]
}