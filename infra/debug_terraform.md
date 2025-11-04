# Validate config
terraform validate

# Preview changes
terraform plan -out=plan.out   # explicit plan file

# Apply planned changes
terraform apply plan.out

# Enable debug logs
export TF_LOG=DEBUG
terraform apply
unset TF_LOG

# Inspect current state
terraform state list
terraform state show <resource>

# Target specific resource
terraform apply -target=<resource>

# Skip refresh if failing
terraform apply -refresh=false
