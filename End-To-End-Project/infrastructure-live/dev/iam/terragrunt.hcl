include {
    path = find_in_parent_folders("root.hcl")
}

terraform {
    source = "../../../infra-structure-modules/iam"
}

inputs = {
environment = "dev"    
}