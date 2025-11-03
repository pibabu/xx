resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_server.id]
  
  # Terraform: Reference the instance profile from iam.tf
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  
  key_name = var.ssh_key_name
  
  # Terraform: Read external file and pass variables
  user_data = templatefile("${path.module}/files/userdata.sh", {
    app_dir  = "/home/ec2-user/fastapi-app"
    app_port = 8000
  })
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  
  # AWS tag: CodeDeploy finds instances by this
  tags = {
    Name        = "${var.app_name}-server"
    Application = var.app_name  # deployed auf alle Instancen mit Tag "fastapi_app" -> Name checken!!
  }
}