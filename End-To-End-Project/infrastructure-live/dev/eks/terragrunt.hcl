include {
    path = find_in_parent_folders("root.hcl")
}

terraform {
    source = "../../../infra-structure-modules/eks"
}
dependency "iam"{
    config_path = "../iam"

    mock_outputs = {
        eks_role_arn = "arn:aws:iam::123456789012:role/mock-role"
    }
    mock_outputs_allowed_terraform_commands = ["plan","validate","init"]
}
dependency "subnet"{
    config_path = "../subnet"

    mock_outputs = {
        subnet_ids = ["mock-subnet-id-1","mock-subnet-id-2"]
    }
    mock_outputs_allowed_terraform_commands = ["plan","validate","init"]
}

inputs = {
environment = "dev"    
iam_role_arn = dependency.iam.outputs.eks_role_arn
subnet_ids = dependency.subnet.outputs.subnet_ids
}