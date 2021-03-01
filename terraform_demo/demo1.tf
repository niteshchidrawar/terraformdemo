provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAYUW3CWBXU547U35Q"
  secret_key = "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"
}
resource "aws_vpc" "demo1" {
  cidr_block        = "190.160.0.0/16"
  instance_tenancy  = "default"

  tags = {
    Name = "demo1"
  }
}

resource "aws_internet_gateway" "demo1_igw" {
 vpc_id = "${aws_vpc.demo1.id}"
 tags = {
    Name = "demo1-igw"
 }
}

resource "aws_eip" "eip" {
  vpc=true
}

  # --  Subnet
data "aws_availability_zones" "azs" {
  state = "available"
}
resource "aws_subnet" "public-subnet-1a" {
  availability_zone = "${data.aws_availability_zones.azs.names[0]}"
  cidr_block        = "190.160.1.0/24"
  vpc_id            = "${aws_vpc.demo1.id}"
  map_public_ip_on_launch = "true"
  tags = {
   Name = "public-subnet-1a"
   }
} 



resource "aws_subnet" "public-subnet-1b" {
  availability_zone = "${data.aws_availability_zones.azs.names[1]}"
  cidr_block        = "190.160.2.0/24"
  vpc_id            = "${aws_vpc.demo1.id}"
  map_public_ip_on_launch = "true"
  tags = {
   Name = "public-subnet-1b"
   }
}

resource "aws_subnet" "private-subnet-1a" {
  availability_zone = "${data.aws_availability_zones.azs.names[0]}"
  cidr_block        = "190.160.3.0/24"
  vpc_id            = "${aws_vpc.demo1.id}"
  tags = {
   Name = "private-subnet-1a"
   }
}


resource "aws_subnet" "private-subnet-1b" {
  availability_zone = "${data.aws_availability_zones.azs.names[1]}"
  cidr_block        = "190.160.4.0/24"
  vpc_id            = "${aws_vpc.demo1.id}"
  tags = {
   Name = "private-subnet-1b"
   }
}

# --------------  NAT Gateway

resource "aws_nat_gateway" "demo1-ngw" {
  allocation_id = "${aws_eip.eip.id}"
  subnet_id = "${aws_subnet.public-subnet-1b.id}"
  tags = {
      Name = "Demo1 Nat Gateway"
  }
}
resource "aws_route_table" "demo1-public-route" {
  vpc_id =  "${aws_vpc.demo1.id}"
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.demo1_igw.id}"
  }

   tags = {
       Name = "demo1-public-route"
   }
}

#--- Subnet Association -----

resource "aws_route_table_association" "arts1a" {
  subnet_id = "${aws_subnet.public-subnet-1a.id}"
  route_table_id = "${aws_route_table.demo1-public-route.id}"
}

resource "aws_route_table_association" "arts1b" {
  subnet_id = "${aws_subnet.public-subnet-1b.id}"
  route_table_id = "${aws_route_table.demo1-public-route.id}"
}

resource "aws_route_table_association" "arts-p-1a" {
  subnet_id = "${aws_subnet.private-subnet-1a.id}"
  route_table_id = "${aws_vpc.demo1.default_route_table_id}"
}

resource "aws_route_table_association" "arts-p-1b" {
  subnet_id = "${aws_subnet.private-subnet-1b.id}"
  route_table_id = "${aws_vpc.demo1.default_route_table_id}"
}






resource "aws_instance" "us-east-1" {
  ami           = "ami-02fe94dee086c0c37" 
  instance_type = "t2.micro"
}
# Create a new load balancer
resource "aws_elb" "bar" {
  name               = "demo1-terraform-elb"
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  access_logs {
    bucket        = "de"
    bucket_prefix = "mo1"
    interval      = 60
  }

  listener {
    instance_port     = 8000
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 8000
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https" 
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:8000/"
    interval            = 30
  }

  instances                   = "${element(aws_instance.base.*id,count.index)}"
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "demo1-elb"
  }
}

resource "aws_placement_group" "test" {
  name     = "test"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "demo1" {
  name                      = "demo1-terraform-test"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 4
  force_delete              = true
  placement_group           = aws_placement_group.test.id
  launch_configuration      = aws_launch_configuration.demo1.name
  vpc_zone_identifier       = "${public-subnet-1a, public-subnet-1b}"

  initial_lifecycle_hook {
    name                 = "demo1"
    default_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"

    notification_metadata = <<EOF
{
  "de": "mo1"
}
EOF

    notification_target_arn = "arn:aws:sqs:us-east-1:444455556666:queue1*"
    role_arn                = "arn:aws:iam::123456789012:role/S3Access"
  }

  tag {
    key                 = "de"
    value               = "mo1"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "lorem"
    value               = "ipsum"
    propagate_at_launch = false
  }
}
