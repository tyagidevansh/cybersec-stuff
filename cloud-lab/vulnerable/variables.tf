# Committed to git with a real-looking password. Both are findings.
variable "db_password" {
  description = "app database password"
  type        = string
  default     = "Sup3rSecret123!"
}

output "db_password" {
  description = "handy for debugging"
  value       = var.db_password
}
