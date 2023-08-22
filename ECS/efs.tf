resource "aws_efs_file_system" "ecs" {
  creation_token = "ecs-files"
}

resource "aws_efs_access_point" "ecs-access" {
  file_system_id = aws_efs_file_system.ecs.id
}

resource "aws_efs_mount_target" "ecs" {
  file_system_id  = aws_efs_file_system.ecs.id
  subnet_id       = aws_subnet.main-1.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name = "efs-access"
  vpc_id = aws_vpc.main.id

  ingress {
    to_port         = 2049
    from_port       = 2049
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}