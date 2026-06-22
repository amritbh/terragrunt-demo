# Get available Az's dynamically
data "aws_availability_zones" "available" {
    state = "available"
}
#create two subnets across two Az's
resource "aws_subnet" "main" {
    count = min(2, length(data.aws_availability_zones.available.names))
    vpc_id = var.vpc_id
    
    #split /16 into /24 subnets automatically
    cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
    availability_zone = data.aws_availability_zones.available.names[count.index]
    map_public_ip_on_launch = true
    
    tags = {
        Name = "${var.environment}-subnet-${count.index + 1}"
        Environment = var.environment

        #required for eks cluster discovery
        "kubernetes.io/cluster/${var.environment}-eks-cluster" = "shared"

        #required for public load balancer
        "kubernetes.io/role/elb" = "1"
        
    }
}