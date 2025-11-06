terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}

# oder löschen -  Terraform defaults to local state