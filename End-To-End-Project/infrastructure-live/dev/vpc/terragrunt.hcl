include {
    path = find_in_parent_folders("root.hcl")
}

terraform {
    source = "../../../infra-structure-modules/vpc"
}

inputs = {
environment = "dev"    
vpc_cidr_block = "10.0.0.0/16"

}