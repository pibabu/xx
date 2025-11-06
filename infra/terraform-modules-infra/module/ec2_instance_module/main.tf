
# resource "tls_private_key" "key" {
#   algorithm = "RSA"
#   rsa_bits  = 4096
# }

# resource "aws_key_pair" "ec2_key_pair" {
#   key_name   = "private-key"
#   public_key = tls_private_key.key.public_key_openssh
  
#   provisioner "local-exec" {
#     command = "echo '${tls_private_key.key.private_key_pem}' > ./private-key.pem"
#   }
  
#   tags = var.tags
# }
### <----- security risk--- key in terraform state


resource "aws_iam_role" "EC2_Service_Role" {
  name = "ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com",
      },
    }],
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_role_permissions" {
  count      = length(var.ec2_role_permissions)
  policy_arn = var.ec2_role_permissions[count.index]
  role       = aws_iam_role.EC2_Service_Role.name
}

resource "aws_iam_role_policy" "s3_artifact_access" {
  name = "S3ArtifactAccess"
  role = aws_iam_role.EC2_Service_Role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowS3ArtifactGetObject",
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = [
          "arn:aws:s3:::${var.codepipeline_s3_bucket}/*"
        ]
      }
    ]
  })
}


resource "aws_iam_instance_profile" "EC2_instance_profile" {
  name = aws_iam_role.EC2_Service_Role.name
  role = aws_iam_role.EC2_Service_Role.id
  tags = var.tags
}

resource "aws_security_group" "ec2_security_group" {
  name        = "ec2-security-group"
  description = "Security group attached with EC2"
  vpc_id      = var.vpc_id  # Passed from VPC module
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.security_group_allowed_ports
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
  
  tags = var.tags
}

resource "aws_instance" "ec2_instance" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id  # Passed from VPC module
  user_data              = file("${path.module}/EC2_user_data.sh")
  iam_instance_profile   = aws_iam_instance_profile.EC2_instance_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  key_name               ="first"  ##checken!
  
  tags = merge(var.tags, {
    Name = var.instance_name
  })
}

resource "aws_eip" "aws_instance_elastic_ip" {
  domain   = "vpc"
  instance = aws_instance.ec2_instance.id
  tags     = var.tags
}