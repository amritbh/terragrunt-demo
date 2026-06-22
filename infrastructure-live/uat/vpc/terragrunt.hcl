
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

vpc_cidr = "10.1.0.0/16"
public_subnet_cidr = "10.1.0.0/24"
vpc_tags = {
    Name = "uat-vpc"
    Environment = "uat"
    Owner = "platform-team"
}
subnet_tags = {
    Name = "uat-subnet"
    Environment = "uat"
    Tier = "public"
}

}