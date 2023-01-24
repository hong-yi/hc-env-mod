data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

resource "aws_s3_bucket" "app_data" {
  bucket = "${var.project_name}-appdata"
}

resource "aws_s3_bucket" "app_data_pub" {
  bucket = "${var.project_name}-public"
}

resource "aws_s3_bucket_policy" "app_data_pub_pol" {
  bucket = aws_s3_bucket.app_data_pub.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "${aws_s3_bucket.app_data_pub.arn}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_vpc" "proj_vpc" {
  cidr_block = var.vpc_cidr_block

  tags = {
    "name" = "vpc-${var.project_name}"
  }
}

resource "aws_internet_gateway" "proj_igw" {
  vpc_id = aws_vpc.proj_vpc.id
}

resource "aws_subnet" "app_subnet" {
  count             = 2
  vpc_id            = aws_vpc.proj_vpc.id
  availability_zone = data.aws_availability_zones.available[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 1, count.index)
}

# resource "aws_subnet" "app_subnet_b" {
#   vpc_id     = aws_vpc.proj_vpc.id
#   cidr_block = cidrsubnet(var.vpc_cidr_block, 1, 1)
# }

resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.proj_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.proj_igw.id
  }
}

resource "aws_route_table_association" "app_rtassoc" {
  count          = 2
  subnet_id      = aws_subnet.app_subnet[count.index].id
  route_table_id = aws_route_table.app_rt.id
}

# resource "aws_route_table_association" "app_rtassoc" {
#   subnet_id      = aws_subnet.app_subnet_b.id
#   route_table_id = aws_route_table.app_rt.id
# }

resource "aws_ecr_repository" "proj_ecr" {
  name         = "ecr-${var.project_name}"
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "proj_ecr_lifecycle_policy" {
  repository = aws_ecr_repository.proj_ecr.name
  policy     = <<EOF
  {
    "rules": [
      {
        "rulePriority": 1,
        "description": "Expire images older than 90 days",
        "selection": {
          "tagStatus": "untagged",
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": 90
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  }
  EOF
}

resource "aws_ecr_repository_policy" "proj_app_ecr_policy" {
  repository = aws_ecr_repository.proj_ecr.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "new policy",
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  }
  EOF
}

resource "aws_ecs_cluster" "app_cluster" {
  name = "ecsc-${var.project_name}"
}

resource "aws_iam_policy" "ecs_task_execution_policy" {
  name = "${var.project_name}-taskExecutionRolePolicy"

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Action" : [
            "s3:PutObject",
            "s3:GetObject"
          ],
          "Resource" : [
            "arn:aws:s3:::${aws_s3_bucket.app_data.bucket}/*",
            "arn:aws:s3:::${aws_s3_bucket.app_data_pub.bucket}/*"
          ]
        }
      ],
    }
  )
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "iamrole-${var.project_name}-taskexec"
  assume_role_policy = jsonencode(
    {
      "Version" : "2008-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "ecs-tasks.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}
resource "aws_iam_role_policy_attachment" "task_exec_rolecw_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "task_exec_role_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "ecr_role" {
  name               = "ecr_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${aws_iam_openid_connect_provider.github.arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecr_policy" {
  name   = "ecr_policy"
  role   = aws_iam_role.ecr_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ecr:*",
      "Resource": "*"
    }
  ]
}
EOF
}

