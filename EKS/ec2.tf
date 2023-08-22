data "aws_ami" "amazon-linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

resource "aws_security_group" "ec2" {
    name = "ec2-efs"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 2049
        to_port = 2049
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "main" {
  ami           = data.aws_ami.amazon-linux.id
  instance_type = "t3.micro"

  security_groups = [aws_security_group.ec2.id]

  subnet_id = aws_subnet.public.id

  associate_public_ip_address = true

  user_data = <<EOF
    #!/bin/bash
    mkdir efs
    mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.eks.dns_name}:/ efs
    echo "Hello World, I come from EFS!" > efs/index.html
  EOF

  depends_on = [aws_efs_mount_target.eks-1]
}