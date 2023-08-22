resource "aws_eks_cluster" "main" {
    name = "EKS-test-3"
    
    role_arn = aws_iam_role.eks-role.arn

    vpc_config {
        subnet_ids = [ aws_subnet.private-1.id, aws_subnet.private-2.id ]
    } 
}

resource "aws_eks_fargate_profile" "main" {
    cluster_name = aws_eks_cluster.main.name
    fargate_profile_name = "test-3"

    pod_execution_role_arn = aws_iam_role.eks-fargate.arn
    subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]

    selector {
        namespace = "default"
    }
}

# IAM policies

data "aws_iam_policy_document" "eks-fargate" {
    statement {
        actions = ["sts:AssumeRole"]

        principals {
            type = "Service"
            identifiers = ["eks-fargate-pods.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "eks-fargate" {
    name = "eks-fargate"
    assume_role_policy = data.aws_iam_policy_document.eks-fargate.json
}

resource "aws_iam_role_policy_attachment" "eks-fargate-attachment" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
    role = aws_iam_role.eks-fargate.name
}

data "aws_iam_policy_document" "eks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks-role" {
    name = "eks-role"
    assume_role_policy = data.aws_iam_policy_document.eks.json
}

resource "aws_iam_role_policy_attachment" "eks-cluster-attachment" {
    role = aws_iam_role.eks-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}