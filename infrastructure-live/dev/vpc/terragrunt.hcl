
#include root configuration
include "root" {
    path = find_in_parent_folders("root.hcl")
}

#point to terraform module
terraform {
    source = "../../../infrastructure-modules/vpc"
}

#pass variables values

inputs = {

vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.0.0/24"
vpc_tags = {
    Name = "dev-vpc"
    Environment = "dev"
    Owner = "terragrunt"
}
subnet_tags = {
    Name = "dev-subnet"
    Environment = "dev"
    Tier = "public"
}

}