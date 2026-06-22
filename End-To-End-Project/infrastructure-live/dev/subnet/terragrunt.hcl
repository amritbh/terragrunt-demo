include {
    path = find_in_parent_folders("root.hcl")
}

terraform {
    source = "../../../infra-structure-modules/subnet"
}

dependency "vpc" { 
    config_path = "../vpc"

    mock_outputs = {
        vpc_id = "mock-vpc-id"
    }
    mock_outputs_allowed_terraform_commands = ["plan","validate","init"]
}

inputs = {
environment = "dev" 
vpc_cidr = "10.0.0.0/16"   
vpc_id = dependency.vpc.outputs.vpc_id

}