resource "aws_eks_cluster" "main" {
    name = "${var.environment}-eks-cluster"
    role_arn = var.iam_role_arn
    vpc_config {
        subnet_ids = var.subnet_ids
    }

    tags = {
        Name = "${var.environment}-eks-cluster"
        Environment = var.environment
    }
}