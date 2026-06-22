variable "environment" {
    type = string
}
variable "iam_role_arn" {
    type = string
}
variable "subnet_ids" {
    type = list(string)
}