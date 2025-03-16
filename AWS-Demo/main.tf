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

#module "clusters" {
#   source = "../"
#}

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

# API key for the 'apps-manager' service account to authenticate with the Kafka cluster.
# This API key is bound to the 'apps-manager' service account and is specific to the 'pageviews' Kafka cluster
# in the 'demo' environment. Depends on the role binding to ensure proper permissions.
resource "confluent_api_key" "apps-manager-kafka-api-key" {
  display_name = "apps-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'apps-manager' service account"
  owner {
    id          = confluent_service_account.apps-manager.id
    api_version = confluent_service_account.apps-manager.api_version
    kind        = confluent_service_account.apps-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.demo.id
    }
  }

  depends_on = [
    confluent_role_binding.apps-manager-kafka-cluster-admin
  ]
}

# ---------------------------------------------------------------------------------------------------------

resource "confluent_service_account" "env-manager" {
  display_name = "env-manager"
  description  = "Service account to manage 'pageviews' Kafka cluster"
}

resource "confluent_role_binding" "env-manager-kafka-environment-admin" {
  principal   = "User:${confluent_service_account.env-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.demo.resource_name
}

resource "confluent_api_key" "env-manager-schema-registry-api-key" {
  display_name = "env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.env-manager.id
    api_version = confluent_service_account.env-manager.api_version
    kind        = confluent_service_account.env-manager.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.advanced.id
    api_version = data.confluent_schema_registry_cluster.advanced.api_version
    kind        = data.confluent_schema_registry_cluster.advanced.kind

    environment {
      id = confluent_environment.demo.id
    }
  }

  depends_on = [
    confluent_role_binding.env-manager-kafka-environment-admin
  ]

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_tag" "pii" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  credentials {
    key    = confluent_api_key.env-manager-schema-registry-api-key.id
    secret = confluent_api_key.env-manager-schema-registry-api-key.secret
  }

  name        = "PII"
  description = "Personally identifiable information"
}

# ***************************************************************** #
# T O P I C S - Topics                                              #
# ***************************************************************** #

resource "confluent_kafka_topic" "users" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "users"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "pageviews" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "pageviews"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_topic" "users-smt" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "users-smt"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

# ***************************************************************** #
# G O V E R N A N C E - Governance                                  #
# ***************************************************************** #

# Apply the Tag/BusinessMetadata on a topic
resource "confluent_tag_binding" "pii-topic-tagging" {
  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.advanced.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.advanced.rest_endpoint
  credentials {
    key    = confluent_api_key.env-manager-schema-registry-api-key.id
    secret = confluent_api_key.env-manager-schema-registry-api-key.secret
  }

  tag_name    = confluent_tag.pii.name
  entity_name = "${data.confluent_schema_registry_cluster.advanced.id}:${confluent_kafka_cluster.standard.id}:${confluent_kafka_topic.users.topic_name}"
  entity_type = local.topic_entity_type
}

# ***************************************************************** #
# A U T H O R I Z A T I O N - Authorization                         #
# ***************************************************************** #

resource "confluent_service_account" "app-consumer" {
  display_name = "app-consumer"
  description  = "Service account to consume from 'users' topic of 'pageviews' Kafka cluster"
}

resource "confluent_api_key" "app-consumer-kafka-api-key" {
  display_name = "app-consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-consumer' service account"
  owner {
    id          = confluent_service_account.app-consumer.id
    api_version = confluent_service_account.app-consumer.api_version
    kind        = confluent_service_account.app-consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.demo.id
    }
  }
}

resource "confluent_kafka_acl" "app-producer-write-on-topic-users" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-producer-write-on-topic-users-smt" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users-smt.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-producer-write-on-topic-pageviews" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.pageviews.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_service_account" "app-producer" {
  display_name = "app-producer"
  description  = "Service account to produce to 'users' topic of 'pageviews' Kafka cluster"
}

resource "confluent_api_key" "app-producer-kafka-api-key" {
  display_name = "app-producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-producer' service account"
  owner {
    id          = confluent_service_account.app-producer.id
    api_version = confluent_service_account.app-producer.api_version
    kind        = confluent_service_account.app-producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.demo.id
    }
  }
}

// Note that in order to consume from a topic, the principal of the consumer ('app-consumer' service account)
// needs to be authorized to perform 'READ' operation on both Topic and Group resources:
// confluent_kafka_acl.app-consumer-read-on-topic, confluent_kafka_acl.app-consumer-read-on-group.
// https://docs.confluent.io/platform/current/kafka/authorization.html#using-acls
resource "confluent_kafka_acl" "app-consumer-read-on-topic-users" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-consumer-read-on-topic-users-smt" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users-smt.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-consumer-read-on-topic-pageviews" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.pageviews.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-consumer-read-on-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "GROUP"
  // The existing values of resource_name, pattern_type attributes are set up to match Confluent CLI's default consumer group ID ("confluent_cli_consumer_<uuid>").
  // https://docs.confluent.io/confluent-cli/current/command-reference/kafka/topic/confluent_kafka_topic_consume.html
  // Update the values of resource_name, pattern_type attributes to match your target consumer group ID.
  // https://docs.confluent.io/platform/current/kafka/authorization.html#prefixed-acls
  resource_name = "confluent_cli_consumer_"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

# ***************************************************************** #
# C O N N E C T O R S - Connectors & Service Account                #
# ***************************************************************** #

resource "confluent_service_account" "app-connector" {
  display_name = "app-connector"
  description  = "Service account of S3 Sink Connector to consume from 'users' topic of 'pageviews' Kafka cluster"
}


resource "confluent_kafka_acl" "app-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic-users" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic-users-smt" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users-smt.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic-pageviews" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.pageviews.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-read-on-target-topic-pageviews" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.pageviews.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-read-on-target-topic-users" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-read-on-target-topic-users-smt" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.users-smt.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-create-on-data-preview-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "data-preview"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-data-preview-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "data-preview"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-create-on-dlq-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-dlq-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "dlq-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-create-on-success-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "success-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-success-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "success-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-create-on-error-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "error-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-error-lcc-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "error-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-read-on-connect-lcc-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "GROUP"
  resource_name = "connect-lcc"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.apps-manager-kafka-api-key.id
    secret = confluent_api_key.apps-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "users_source" {
  environment {
    id = confluent_environment.demo.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "users_source"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "kafka.topic"              = confluent_kafka_topic.users.topic_name
    "output.data.format"       = "JSON_SR"
    "quickstart"               = "USERS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic-users,
    confluent_kafka_acl.app-connector-create-on-data-preview-topics,
    confluent_kafka_acl.app-connector-write-on-data-preview-topics,
  ]
}

resource "confluent_connector" "users_smt_source" {
  environment {
    id = confluent_environment.demo.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"                  = "DatagenSource"
    "name"                             = "users_smt_source"
    "kafka.auth.mode"                  = "SERVICE_ACCOUNT"
    "kafka.service.account.id"         = confluent_service_account.app-connector.id
    "kafka.topic"                      = confluent_kafka_topic.users-smt.topic_name
    "output.data.format"               = "JSON_SR"
    "quickstart"                       = "USERS"
    "tasks.max"                        = "1"
    "transforms"                       = "MaskField"
    "transforms.MaskField.type"        = "org.apache.kafka.connect.transforms.MaskField$Value"
    "transforms.MaskField.fields"      = "gender"
    "transforms.MaskField.replacement" = "***"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic-users-smt,
    confluent_kafka_acl.app-connector-create-on-data-preview-topics,
    confluent_kafka_acl.app-connector-write-on-data-preview-topics,
  ]
}

resource "confluent_connector" "pageviews_source" {
  environment {
    id = confluent_environment.demo.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "pageviews_source"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "kafka.topic"              = confluent_kafka_topic.pageviews.topic_name
    "output.data.format"       = "JSON_SR"
    "quickstart"               = "PAGEVIEWS"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic-pageviews,
    confluent_kafka_acl.app-connector-create-on-data-preview-topics,
    confluent_kafka_acl.app-connector-write-on-data-preview-topics,
  ]
}

resource "confluent_connector" "s3_sink" {
  environment {
    id = confluent_environment.demo.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html#configuration-properties
  config_sensitive = {
    "aws.access.key.id"     = var.s3_access_key_id
    "aws.secret.access.key" = var.s3_secret_key
  }

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html#configuration-properties
  config_nonsensitive = {
    "topics"                   = confluent_kafka_topic.pageviews.topic_name
    "input.data.format"        = "JSON_SR"
    "connector.class"          = "S3_SINK"
    "name"                     = "S3_SINK"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "s3.bucket.name"           = "oporus-buckets"
    "output.data.format"       = "JSON"
    "time.interval"            = "HOURLY"
    "flush.size"               = "1000"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-read-on-target-topic-pageviews,
    confluent_kafka_acl.app-connector-create-on-dlq-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-dlq-lcc-topics,
    confluent_kafka_acl.app-connector-create-on-success-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-success-lcc-topics,
    confluent_kafka_acl.app-connector-create-on-error-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-error-lcc-topics,
    confluent_kafka_acl.app-connector-read-on-connect-lcc-group,
  ]

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_connector" "dynamo_sink" {
  environment {
    id = confluent_environment.demo.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html#configuration-properties
  config_sensitive = {
    "aws.access.key.id"     = var.dynamo_access_key_id
    "aws.secret.access.key" = var.dynamo_secret_key
  }

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-amazon-dynamo-db-sink.html#configuration-properties
  config_nonsensitive = {
    "topics"                   = confluent_kafka_topic.users.topic_name
    "input.data.format"        = "JSON_SR"
    "connector.class"          = "DynamoDbSink"
    "name"                     = "DynamoDb_Sink"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    //"aws.dynamodb.pk.hash"     = "value.userid"
    //"aws.dynamodb.pk.sort"     = "value.userid"
    "tasks.max" = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-read-on-target-topic-users,
    confluent_kafka_acl.app-connector-create-on-dlq-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-dlq-lcc-topics,
    confluent_kafka_acl.app-connector-create-on-success-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-success-lcc-topics,
    confluent_kafka_acl.app-connector-create-on-error-lcc-topics,
    confluent_kafka_acl.app-connector-write-on-error-lcc-topics,
    confluent_kafka_acl.app-connector-read-on-connect-lcc-group,
  ]
}

# ***************************************************************** #
# K S Q L D B - ksqlDB Cluster & Service Account                    #
# ***************************************************************** #

resource "confluent_service_account" "app-ksql" {
  display_name = "app-ksql"
  description  = "Service account for ksqlDB cluster"
}

resource "confluent_role_binding" "app-ksql-all-topic" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_kafka_cluster.standard.rbac_crn}/kafka=${confluent_kafka_cluster.standard.id}/topic=*"
}

resource "confluent_role_binding" "app-ksql-all-group" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_kafka_cluster.standard.rbac_crn}/kafka=${confluent_kafka_cluster.standard.id}/group=*"
}

resource "confluent_role_binding" "app-ksql-all-transactions" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_kafka_cluster.standard.rbac_crn}/kafka=${confluent_kafka_cluster.standard.id}/transactional-id=*"
}

# ResourceOwner roles above are for KSQL service account to read/write data from/to kafka,
# this role instead is needed for giving access to the Ksql cluster.
resource "confluent_role_binding" "app-ksql-ksql-admin" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "KsqlAdmin"
  crn_pattern = confluent_ksql_cluster.main.resource_name
}

resource "confluent_role_binding" "app-ksql-schema-registry-resource-owner" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = format("%s/%s", data.confluent_schema_registry_cluster.advanced.resource_name, "subject=*")
}

resource "confluent_ksql_cluster" "main" {
  display_name = "ksql_cluster_0"
  csu          = 1
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  credential_identity {
    id = confluent_service_account.app-ksql.id
  }
  environment {
    id = confluent_environment.demo.id
  }
  depends_on = [
    confluent_role_binding.app-ksql-schema-registry-resource-owner,
    data.confluent_schema_registry_cluster.advanced
  ]
}

resource "confluent_api_key" "app-ksqldb-api-key" {
  display_name = "app-ksqldb-api-key"
  description  = "KsqlDB API Key that is owned by 'app-ksql' service account"
  owner {
    id          = confluent_service_account.app-ksql.id
    api_version = confluent_service_account.app-ksql.api_version
    kind        = confluent_service_account.app-ksql.kind
  }

  managed_resource {
    id          = confluent_ksql_cluster.main.id
    api_version = confluent_ksql_cluster.main.api_version
    kind        = confluent_ksql_cluster.main.kind

    environment {
      id = confluent_environment.demo.id
    }
  }
}

# Creates a Confluent Flink Compute Pool named 'standard_compute_pool'.
# This pool runs on AWS in the 'eu-west-1' region with a maximum of 10 CFUs (Compute Flink Units).
# The pool is associated with the specified 'demo' environment.
resource "confluent_flink_compute_pool" "main" {
  display_name = "standard_compute_pool"
  cloud        = "AWS"
  region       = "eu-west-1"
  max_cfu      = 10
  environment {
    id = confluent_environment.demo.id
  }
}

locals {
  topic_entity_type = "kafka_topic"
  //schema_entity_type = "sr_schema"
  //record_entity_type = "sr_record"
}
