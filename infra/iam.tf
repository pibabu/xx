# ==========================================
# EC2 ROLE
# ==========================================
# AWS IAM Role
resource "aws_iam_role" "ec2_role" {
  name = "${var.app_name}-ec2-role"
  
  # AWS trust policy: WHO can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"  # EC2 service can use it
      }
    }]
  })
}

# Terraform: Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ec2_ssm_default" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for S3 artifact access
resource "aws_iam_role_policy" "ec2_s3_artifacts" {
  name = "s3-artifacts-access"
  role = aws_iam_role.ec2_role.id
  
  # AWS permissions policy: WHAT this role can do
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
      ]
    }]
  })
}

# AWS Instance Profile (wrapper for EC2 to use role)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
# Trust policy: Allows EC2 service to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
#....vs.....
# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_deploy_role" {
  name               = "${var.app_name}-ec2-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  
  tags = {
    Name = "${var.app_name}-ec2-role"
  }
}

# Policy 1: SSM Agent Permissions (for Session Manager access)
resource "aws_iam_role_policy" "ssm_agent" {
  name = "SSMAgentPermissions"
  role = aws_iam_role.ec2_deploy_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMAgentPermissions"
        Effect = "Allow"
        Action = [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSSMChannelMessaging"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSSMLegacyMessaging"
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy 2: S3 Access for CodePipeline Artifacts
resource "aws_iam_role_policy" "s3_artifacts" {
  name = "S3ArtifactAccess"
  role = aws_iam_role.ec2_deploy_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ArtifactGetObject"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::codepipeline-eu-central-1-*/*"
        ]
      }
    ]
  })
}

# Instance Profile: Links IAM role to EC2 instance
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile"
  role = aws_iam_role.ec2_deploy_role.name
  
  tags = {
    Name = "${var.app_name}-instance-profile"
  }
}