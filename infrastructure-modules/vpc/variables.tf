#create vatiables for intializing the vpc and subnet
variable "vpc_cidr" {
    type = string
    default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
    type = string
    default = "10.0.0.0/24"
}

variable "vpc_tags" {
    type = map(string)
    default = {
        Name = "default-vpc"
        Environment = "dev"
        Owner = "terraform"

    }
}
 
variable "subnet_tags" {
    type = map(string)
    default = {
        Name = "default-subnet"
        Environment = "dev"
        Tier = "public"
    }

}