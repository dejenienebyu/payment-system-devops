output "elastic_ip" {
  value       = aws_eip.payment_eip.public_ip
  description = "Permanent Elastic IP for EC2"
}

output "server_ip" {
  value = aws_instance.payment_server.public_ip
}

output "health_check_url" {
  value = "http://${aws_instance.payment_server.public_ip}:3000/health"
}

output "payment_api_url" {
  value = "http://${aws_instance.payment_server.public_ip}:3000"
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/payment-system-key.pem ec2-user@${aws_instance.payment_server.public_ip}"
}

output "database_endpoint" {
  value     = aws_db_instance.payment_db.address
  sensitive = true
}

output "eks_cluster_name" {
  value = aws_eks_cluster.payment_cluster.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.payment_cluster.endpoint
}
