variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "shard_count" {
  type    = number
  default = 2
}

variable "redshift_admin_password" {
  description = "Contraseña del usuario administrador de Redshift Serverless"
  type        = string
  sensitive   = true
}