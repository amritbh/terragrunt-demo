
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

vpc_cidr = "10.2.0.0/16"
public_subnet_cidr = "10.2.1.0/24"
vpc_tags = {
    Name = "prod-vpc"
    Environment = "prod"
    Owner = "platform-team"
}
subnet_tags = {
    Name = "prod-subnet"
    Environment = "prod"
    Tier = "public"
}

}