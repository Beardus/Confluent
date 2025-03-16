variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "dynamo_access_key_id" {
  description = "dynamo DB AWS access key"
  type        = string  
  sensitive   = true
}

variable "dynamo_secret_key" {
  description = "dynamo DB AWS secret access key"
  type        = string  
  sensitive   = true
}

variable "s3_access_key_id" {
  description = "s3 AWS access key"
  type        = string  
  sensitive   = true
}

variable "s3_secret_key" {
  description = "s3 AWS secret access key"
  type        = string  
  sensitive   = true
}
