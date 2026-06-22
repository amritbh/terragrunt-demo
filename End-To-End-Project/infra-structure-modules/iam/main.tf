#I am role for eks controle palane 
resource "aws_iam_role" "eks-cluster-role" {
    name = "${var.environment}-eks-cluster-role"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "eks.amazonaws.com"
                }
                Action = "sts:AssumeRole"

            }
        ]
    })
    tags = {
        Environment = var.environment
    }
}
#attach policies to the role
resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
    role       = aws_iam_role.eks-cluster-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks-service-policy" {
    role       = aws_iam_role.eks-cluster-role.name
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

    