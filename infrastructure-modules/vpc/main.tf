resource "aws_vpc" "main"{
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = var.vpc_tags
}
resource "aws_subnet" "public"{
    vpc_id = aws_vpc.main.id
    cidr_block = var.public_subnet_cidr
    map_public_ip_on_launch = true

    tags = var.subnet_tags
}

    
    

