output "resource-ids" {
  value = <<-EOT
  # Environment ###########################################################
  Environment ID:                       ${confluent_environment.demo.id}
  Kafka Cluster ID:                     ${confluent_kafka_cluster.standard.id}
  Kafka Cluster Bootstrap               ${confluent_kafka_cluster.standard.bootstrap_endpoint}
  EOT
  

  sensitive = true
}
