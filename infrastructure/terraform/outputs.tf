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
