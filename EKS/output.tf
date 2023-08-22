output "efs_id" {
    description = "id of efs"
    value = aws_efs_file_system.eks.id
}