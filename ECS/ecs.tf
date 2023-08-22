# IAM Policy

data "aws_iam_policy_document" "ecs-tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs-efs" {
    statement {
        actions = [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientWrite"
        ]

        resources = [aws_efs_file_system.ecs.arn]

        condition {
            test = "StringEquals"
            variable = "elasticfilesystem:AccessPointArn"

            values = [aws_efs_access_point.ecs-access.arn]
        }
    }
}

resource "aws_iam_policy" "ecs-efs" {
    name = "ecs-efs"
    path = "/"
    policy = data.aws_iam_policy_document.ecs-efs.json
}

resource "aws_iam_role" "ecs-efs-role" {
    name = "ecs-efs-role"
    assume_role_policy = data.aws_iam_policy_document.ecs-tasks.json
}

resource "aws_iam_role_policy_attachment" "ecs_efs_policy_attachment" {
    role = aws_iam_role.ecs-efs-role.name
    policy_arn = aws_iam_policy.ecs-efs.arn
}

resource "aws_iam_role" "ecs-tasks-role" {
    name = "ecs-tasks-role"
    assume_role_policy = data.aws_iam_policy_document.ecs-tasks.json
}

resource "aws_iam_role_policy_attachment" "ecs_ecr_policy_attachment" {
    role = aws_iam_role.ecs-tasks-role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Fargate

resource "aws_ecs_cluster" "cluster" {
    name = "Test-3-apache"
}

resource "aws_ecs_task_definition" "ecs-task" {
    family = "Test-3-apache"

    network_mode = "awsvpc"

    execution_role_arn = aws_iam_role.ecs-tasks-role.arn

    task_role_arn = aws_iam_role.ecs-efs-role.arn

    container_definitions = <<DEFINITION
    [
        {
            "name": "Test-3-apache",
            "image":"nginx",
            "portMappings": [
                {
                    "containerPort": 80,
                    "hostPort": 80,
                    "protocol": "tcp"
                }
            ],
            "essential": true,
            "mountPoints": [
                {
                    "containerPath": "/usr/share/nginx/html",
                    "sourceVolume": "ecs-files"
                }
            ]
           }
    ]
    DEFINITION
    
    requires_compatibilities = ["FARGATE"]

    cpu = 256
    memory = 1024

    volume {
        name = "ecs-files"

        efs_volume_configuration {
          file_system_id = aws_efs_file_system.ecs.id
          transit_encryption = "ENABLED"
          authorization_config {
            access_point_id = aws_efs_access_point.ecs-access.id
            iam = "ENABLED"
          }
        }
    }
}

resource "aws_ecs_service" "service" {
    name = "Test-3-apache"
    cluster = aws_ecs_cluster.cluster.id
    task_definition = aws_ecs_task_definition.ecs-task.arn
    desired_count = 1

    launch_type = "FARGATE"

    network_configuration {
        subnets = [aws_subnet.main-1.id]
        security_groups = [aws_security_group.ecs-sg.id]
        assign_public_ip = true
    }

    depends_on = [aws_instance.main]
}

# Security Group

resource "aws_security_group" "ecs-sg" {
    name = "ECS-SG"
    vpc_id = aws_vpc.main.id

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