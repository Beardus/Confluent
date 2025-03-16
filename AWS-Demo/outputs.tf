output "resource-ids" {
  value = <<-EOT
  # Environment ###########################################################
  Environment ID:                       ${confluent_environment.demo.id}
  Kafka Cluster ID:                     ${confluent_kafka_cluster.standard.id}
  Kafka Cluster Bootstrap               ${confluent_kafka_cluster.standard.bootstrap_endpoint}

  # ksqlDB ################################################################
  ksqlDB Cluster ID:                    ${confluent_ksql_cluster.main.id}
  ksqlDB Cluster API Endpoint:          ${confluent_ksql_cluster.main.rest_endpoint}
  KSQL Service Account ID:              ${confluent_service_account.app-ksql.id}

  # Schema Registry #######################################################
  Schema Registry ID:                   ${data.confluent_schema_registry_cluster.advanced.id}
  Schema Registry Bootstrap:            ${data.confluent_schema_registry_cluster.advanced.rest_endpoint}
  Schema Registry's API Key:            "${confluent_api_key.env-manager-schema-registry-api-key.id}"
  Schema Registry's API Secret:         "${confluent_api_key.env-manager-schema-registry-api-key.secret}"

  # Connectors ############################################################
  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.apps-manager.display_name}:                     ${confluent_service_account.apps-manager.id}
  ${confluent_service_account.apps-manager.display_name}'s Kafka API Key:     "${confluent_api_key.apps-manager-kafka-api-key.id}"
  ${confluent_service_account.apps-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.apps-manager-kafka-api-key.secret}"

  ${confluent_service_account.app-producer.display_name}:                    ${confluent_service_account.app-producer.id}
  ${confluent_service_account.app-producer.display_name}'s Kafka API Key:    "${confluent_api_key.app-producer-kafka-api-key.id}"
  ${confluent_service_account.app-producer.display_name}'s Kafka API Secret: "${confluent_api_key.app-producer-kafka-api-key.secret}"

  ${confluent_service_account.app-consumer.display_name}:                    ${confluent_service_account.app-consumer.id}
  ${confluent_service_account.app-consumer.display_name}'s Kafka API Key:    "${confluent_api_key.app-consumer-kafka-api-key.id}"
  ${confluent_service_account.app-consumer.display_name}'s Kafka API Secret: "${confluent_api_key.app-consumer-kafka-api-key.secret}"

  In order to use the Confluent CLI v2 to produce and consume messages from topic '${confluent_kafka_topic.users.topic_name}' using Kafka API Keys
  of ${confluent_service_account.app-producer.display_name} and ${confluent_service_account.app-consumer.display_name} service accounts
  run the following commands:

  # 1. Log in to Confluent Cloud
  $ confluent login

  # 2. Produce key-value records to topic '${confluent_kafka_topic.users.topic_name}' by using ${confluent_service_account.app-producer.display_name}'s Kafka API Key
  $ confluent kafka topic produce ${confluent_kafka_topic.users.topic_name} --environment ${confluent_environment.demo.id} --cluster ${confluent_kafka_cluster.standard.id} --api-key "${confluent_api_key.app-producer-kafka-api-key.id}" --api-secret "${confluent_api_key.app-producer-kafka-api-key.secret}"
  # Enter a few records and then press 'Ctrl-C' when you're done.
  # Sample records:
  # {"number":1,"date":18500,"shipping_address":"899 W Evelyn Ave, Mountain View, CA 94041, USA","cost":15.00}
  # {"number":2,"date":18501,"shipping_address":"1 Bedford St, London WC2E 9HG, United Kingdom","cost":5.00}
  # {"number":3,"date":18502,"shipping_address":"3307 Northland Dr Suite 400, Austin, TX 78731, USA","cost":10.00}

  # 3. Consume records from topic '${confluent_kafka_topic.users.topic_name}' by using ${confluent_service_account.app-consumer.display_name}'s Kafka API Key
  $ confluent kafka topic consume ${confluent_kafka_topic.users.topic_name} --from-beginning --environment ${confluent_environment.demo.id} --cluster ${confluent_kafka_cluster.standard.id} --api-key "${confluent_api_key.app-consumer-kafka-api-key.id}" --api-secret "${confluent_api_key.app-consumer-kafka-api-key.secret}"
  # When you are done, press 'Ctrl-C'.

  # ksqlDB ####################################################

  # 1. Log in to Confluent Cloud
  $ confluent login

  # 2. Start ksqlDB's interactive CLI and connect it to your ksqlDB cluster. You'll need the ksqlDB API credentials you created, as well as the ksqlDB endpoint.
  # Please note that the ksqlDB cluster might take a few minutes to accept connections.
  $ docker run --rm -it confluentinc/ksqldb-cli:latest ksql \
       -u "${confluent_api_key.app-ksqldb-api-key.id}" \
       -p "${confluent_api_key.app-ksqldb-api-key.secret}" \
       "${confluent_ksql_cluster.main.rest_endpoint}"

  # 3. Make sure you can see "Server Status: RUNNING", otherwise (for example, "Server Status: <unknown>") enter `exit` and repeat step #3 in a few minutes.

  # 4. Once you are connected, you can create a ksqlDB stream. A stream essentially associates a schema with an underlying Kafka topic.
  CREATE STREAM ${confluent_kafka_topic.users.topic_name}_stream (id INTEGER KEY, gender STRING, name STRING, age INTEGER) WITH (kafka_topic='${confluent_kafka_topic.users.topic_name}', partitions=${confluent_kafka_topic.users.partitions_count}, value_format='JSON');

  # 5. Insert some data into the stream you just created.
  INSERT INTO ${confluent_kafka_topic.users.topic_name}_stream (id, gender, name, age) VALUES (0, 'female', 'sarah', 42);
  INSERT INTO ${confluent_kafka_topic.users.topic_name}_stream (id, gender, name, age) VALUES (1, 'male', 'john', 28);

  # 6. To confirm your insertion was successful, run a SELECT statement on your stream:
  SELECT * FROM ${confluent_kafka_topic.users.topic_name}_stream;

  # When you are done, press 'Ctrl-C'.
  EOT

  sensitive = true
}
