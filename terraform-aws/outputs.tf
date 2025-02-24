output "instance_public_ip" {
  description = "IP público da instância Windows"
  value       = aws_instance.windows_vm.public_ip
}
