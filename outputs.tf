output "bastion_public_ip" {
  value = module.ec2.bastion_public_ip
}

output "private_instance_private_ip" {
  value = module.ec2.private_instance_private_ip
}
