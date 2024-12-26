terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.11.0"
    }
  }
}

# Configure the Confluent provider with API credentials.
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Define a Confluent environment named "Demo" with an "Advanced" Stream Governance package.
resource "confluent_environment" "demo" {
  display_name = "Demo"

  stream_governance {
    package = "ADVANCED"
  }
}

# Retrieve information about an existing Schema Registry cluster for use in the "Demo" environment.
# Note: This data resource depends on the Kafka cluster to be fully set up (referenced as "confluent_kafka_cluster.standard").
data "confluent_schema_registry_cluster" "advanced" {
  environment {
    id = confluent_environment.demo.id
  }

  depends_on = [
    confluent_kafka_cluster.standard
  ]
}

# Create a Confluent Kafka cluster named "pageviews" with standard configuration.
# This cluster will be single-zone, hosted on AWS in the "eu-west-1" region, and part of the "Demo" environment.
resource "confluent_kafka_cluster" "standard" {
  display_name = "sandbox"
  availability = "SINGLE_ZONE"
  cloud        = "AWS"
  region       = "eu-west-1"
  standard {}
  environment {
    id = confluent_environment.demo.id
  }
}

# Service account for managing the 'pageviews' Kafka cluster.
resource "confluent_service_account" "apps-manager" {
  display_name = "apps-manager"
  description  = "Service account to manage 'pageviews' Kafka cluster"
}

# Role binding to grant 'CloudClusterAdmin' permissions to the 'apps-manager' service account for managing the Kafka cluster.
resource "confluent_role_binding" "apps-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.apps-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.standard.rbac_crn
}
