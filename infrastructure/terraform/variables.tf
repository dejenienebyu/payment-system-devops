variable "aws_region" {
  default = "eu-north-1"
}

variable "ami_id" {
  description = "Amazon Linux 2 - eu-north-1"
  default     = "ami-017535a27f2ac0ce3"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  default = "payment-system-key"
}

variable "db_username" {
  description = "Database admin username"
  default     = "paymentadmin"
}

variable "db_password" {
  description = "Database password"
  sensitive   = true
  default     = "PaymentDB#2026!"
}
