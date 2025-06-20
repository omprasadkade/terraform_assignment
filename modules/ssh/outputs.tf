output "private_key_path" {
  value = local_file.private_key.filename
}

output "key_name" {
  value = aws_key_pair.generated.key_name
}
