output "eks_role_id" {
    value = aws_iam_role.eks-cluster-role.id
}

output "eks_role_arn" {
    value = aws_iam_role.eks-cluster-role.arn
}