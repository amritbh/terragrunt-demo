remote_state {
    backend = "s3"
    generate = {
        path = "remote-state.tf"
        if_exists = "overwrite_terragrunt"
    }
    config = {
        bucket = "s3-terraform-terragrunt-state"
        key = "${path_relative_to_include()}/terraform.tfstate"
        region = "us-east-1"
        encrypt = true
        dynamodb_table = "s3-terraform-terragrunt-state-locks"
    }
}
generate "provider" {
    path = "provider.tf"
    if_exists = "overwrite_terragrunt"
    contents = <<EOF
    provider "aws" {
        region = "us-east-1"
    }
    EOF
}     