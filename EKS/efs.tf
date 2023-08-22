resource "aws_efs_file_system" "eks" {
  creation_token = "eks-files"
}

resource "aws_efs_access_point" "eks-access" {
  file_system_id = aws_efs_file_system.eks.id
}

resource "aws_efs_mount_target" "eks-1" {
  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.efs.id]
}


resource "aws_efs_mount_target" "eks-2" {
  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = aws_subnet.private-1.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "eks-3" {
  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = aws_subnet.private-2.id
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