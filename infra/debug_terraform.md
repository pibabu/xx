# Enable debug logging (PowerShell syntax)
$env:TF_LOG = "TRACE"
$env:TF_LOG_PATH = "terraform.log"

# Disable when done
Remove-Item Env:\TF_LOG
Remove-Item Env:\TF_LOG_PATH

# Log Levels
$env:TF_LOG = "TRACE"   # Most verbose - everything
$env:TF_LOG = "DEBUG"   # Detailed API calls
$env:TF_LOG = "INFO"    # General info (recommended start)
$env:TF_LOG = "WARN"    # Warnings only
$env:TF_LOG = "ERROR"   # Errors only

# Lifecycle elastic IP Problem

alles löschen außer eip:

terraform destroy \
  -target=aws_eip_association.eip_assoc \
  -target=module.ec2_instance_module \
  -target=module.vpc

---> geht nicht

## debug ec2

sudo cat /var/log/cloud-init-output.log