variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "gcs_credentials" {
  description = "gcs_credentials"
  type        = string  
  sensitive   = true
}

variable "post_password" {
  description = "post_password"
  type        = string  
  sensitive   = true
}

variable "sales_user" {
  description = "sales_user"
  type        = string  
  sensitive   = true
}

variable "sales_password" {
  description = "sales_passwrod"
  type        = string  
  sensitive   = true
}

variable "sales_token" {
  description = "sales_token"
  type        = string  
  sensitive   = true
}

variable "sales_key" {
  description = "sales_key"
  type        = string  
  sensitive   = true
}

variable "sales_secret" {
  description = "sales_secret"
  type        = string  
  sensitive   = true
}
