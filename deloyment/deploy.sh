#!/bin/bash
#Deployment script for homelab

#Setting environment variables
VALID_APPLICATIONS=("influxdb" "kafka" "infra" "msql" "neo4j" "ollama" "opensearch" "rabbitmq" "zookeeper" "load-generator")
VALID_DEPLOYMENT_ACTIONS=("deploy" "rollback")
VERSION=$(uuidgen)
GIT_BASE_URL="https://raw.githubusercontent.com/kicapman1x"
RETENTION_CYCLES=3

#Help function
print_help() {
  echo "Usage: $0 <application_name> <deploy|rollback> <rollback_version - if applicable>"
  echo "Deploy/rollback the specified application to Han's Homelab environment."
  echo "Valid application names are:"
  for app in "${VALID_APPLICATIONS[@]}"; do
    echo "  - $app"
  done
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  print_help
  exit 0
fi

#Arguments are mandatory
APPLICATION_NAME=$1
DEPLOY_ROLLBACK=$2
ROLLBACK_VERSION=$3

if [ -z "$APPLICATION_NAME" ]; then
  echo "Error: Application name is required. Choose from the following:"
  print_help
  exit 1
fi

if [ -z "$DEPLOY_ROLLBACK" ]; then
  echo "Error: Deployment action is required. Specify 'deploy' or 'rollback'."
  exit 1
fi

#Validate parameters
if [[ ! " ${VALID_APPLICATIONS[*]} " =~ " ${APPLICATION_NAME} " ]]; then
  echo "Error: Invalid application name."
  print_help
  exit 1
fi

if [[ ! " ${VALID_DEPLOYMENT_ACTIONS[*]} " =~ " ${DEPLOY_ROLLBACK} " ]]; then
  echo "Error: Invalid deployment action. Use 'deploy' or 'rollback'."
  exit 1
fi

if [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  if [ -z "$ROLLBACK_VERSION" ]; then
    echo "Error: Rollback version is required for rollback action."
    exit 1
  fi
fi

#Helper functions
retrieve_pw() {
  local secret_file="$1"
  local ori_file="$2"
  local key="$3"
  local placeholder="$4"
  local delimiter="$5"

  if [ -f "$secret_file" ]; then
    SECRET_VALUE=$(cat "$secret_file" | grep -i $key | cut -d "$delimiter" -f2)
    if [ -n "$SECRET_VALUE" ]; then
      sed -i "s/${placeholder}/${SECRET_VALUE}/g" "$ori_file"
    else
      echo "Error: Key $key not found in secret file $secret_file."
      exit 1
    fi
  else
    echo "Error: Secret file $secret_file not found."
    exit 1
  fi
}

#Functions for deployment, backup, and rollback
#Rollback 
influxdb_rollback() {
  echo "Rolling back InfluxDB to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/influx.conf" "$INFLUX_HOME/data/influxdbv2/"
  cp -r "$VERSION_DIR/grafana.ini" "$GRF_HOME/conf/"
  cp -r "$VERSION_DIR/ldap.toml" "$GRF_HOME/conf/"
  echo "InfluxDB rollback to version $ROLLBACK_VERSION completed."
}

kafka_rollback() {
  echo "Rolling back Kafka to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/server.properties" "$KAFKA_HOME/config/"
  cp -r "$VERSION_DIR/ssl-client.properties" "$KAFKA_HOME/config/"
  cp -r "$VERSION_DIR/publisher" "$HOME/apps/kafka/"
  echo "Kafka rollback to version $ROLLBACK_VERSION completed."
}

mysql_rollback() {
  echo "Rolling back MySQL to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/db1/my.cnf" "$MSQL_DB1_HOME/config/my.cnf"
  cp -r "$VERSION_DIR/db1/start.sh" "$MSQL_HOME/db1/bin/start.sh"
  cp -r "$VERSION_DIR/db2/my.cnf" "$MSQL_DB2_HOME/config/my.cnf"
  cp -r "$VERSION_DIR/db2/start.sh" "$MSQL_HOME/db2/bin/start.sh"
  echo "MySQL rollback to version $ROLLBACK_VERSION completed."
}

neo4j_rollback() {
  echo "Rolling back Neo4j to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/neo4j.conf" "$NEO4J_HOME/conf/"
  cp -r "$VERSION_DIR/.env" "$NEO4J_HOME/../bin/.env"
  cp -r "$VERSION_DIR/start.sh" "$NEO4J_HOME/../bin/start.sh"
  cp -r "$VERSION_DIR/requirements.txt" "$NEO4J_HOME/../bin/requirements.txt"
  cp -r "$VERSION_DIR/knowledge_ingest.py" "$NEO4J_HOME/../bin/knowledge_ingest.py"
  cp -r "$VERSION_DIR/knowledge_query.py" "$NEO4J_HOME/../bin/knowledge_query.py"
  echo "Neo4j rollback to version $ROLLBACK_VERSION completed."
}

rabbitmq_rollback() {
  echo "Rolling back RabbitMQ to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/rabbitmq.conf" "$RABBITMQ_HOME/etc/rabbitmq/rabbitmq.conf"
  echo "RabbitMQ rollback to version $ROLLBACK_VERSION completed."
}

load_generator_rollback() {
  echo "Rolling back Load-Generator to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/.env" "$LOAD_GEN_HOME/bin/.env"
  cp -r "$VERSION_DIR/requirements.txt" "$LOAD_GEN_HOME/bin/requirements.txt"
  cp -r "$VERSION_DIR/start.sh" "$LOAD_GEN_HOME/bin/start.sh"
  cp -r "$VERSION_DIR/source-data-interface.py" "$LOAD_GEN_HOME/bin/source-data-interface.py"
  cp -r "$VERSION_DIR/passenger-svc.py" "$LOAD_GEN_HOME/bin/passenger-svc.py"
  echo "Load-Generator rollback to version $ROLLBACK_VERSION completed."
}

#Back up existing deployment if it exists
influxdb_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  cp -r "$INFLUX_HOME/data/influxdbv2/influx.conf" "$BACKUP_DIR/"
  cp -r "$GRF_HOME/conf/grafana.ini" "$BACKUP_DIR/"
  cp -r "$GRF_HOME/conf/ldap.toml" "$BACKUP_DIR/"
  cp -r "$TELEGRAF_HOME/etc/telegraf/telegraf.conf" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

kafka_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  cp -r "$KAFKA_HOME/config/server.properties" "$BACKUP_DIR/"
  cp -r "$KAFKA_HOME/config/ssl-client.properties" "$BACKUP_DIR/"
  cp -r "$HOME/apps/kafka/publisher" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

mysql_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  mkdir -p "$BACKUP_DIR/db1"
  cp -r "$MSQL_DB1_HOME/config/my.cnf" "$BACKUP_DIR/db1/my.cnf"
  cp -r "$MSQL_HOME/db1/bin/start.sh" "$BACKUP_DIR/db1/start.sh"
  mkdir -p "$BACKUP_DIR/db2"
  cp -r "$MSQL_DB2_HOME/config/my.cnf" "$BACKUP_DIR/db2/my.cnf"
  cp -r "$MSQL_HOME/db2/bin/start.sh" "$BACKUP_DIR/db2/start.sh"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

neo4j_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  cp -r "$NEO4J_HOME/conf/neo4j.conf" "$BACKUP_DIR/"
  cp -r "$NEO4J_HOME/../bin/.env" "$BACKUP_DIR/"
  cp -r "$NEO4J_HOME/../bin/start.sh" "$BACKUP_DIR/"
  cp -r "$NEO4J_HOME/../bin/requirements.txt" "$BACKUP_DIR/"
  cp -r "$NEO4J_HOME/../bin/knowledge_ingest.py" "$BACKUP_DIR/"
  cp -r "$NEO4J_HOME/../bin/knowledge_query.py" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

rabbitmq_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  cp -r "$RABBITMQ_HOME/etc/rabbitmq/rabbitmq.conf" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

load_generator_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -p "$BACKUP_DIR"
  cp -r "$LOAD_GEN_HOME/bin/.env" "$BACKUP_DIR/"
  cp -r "$LOAD_GEN_HOME/bin/requirements.txt" "$BACKUP_DIR/"
  cp -r "$LOAD_GEN_HOME/bin/start.sh" "$BACKUP_DIR/"
  cp -r "$LOAD_GEN_HOME/bin/source-data-interface.py" "$BACKUP_DIR/"
  cp -r "$LOAD_GEN_HOME/bin/passenger-svc.py" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

#Deploy
influxdb_deploy() {
  echo "Starting InfluxDB deployment..."
  INFLUX_REPO="$GIT_BASE_URL/influxdb-setup/refs/heads/main"
  curl -fsSL -o $HOME/apps/tmp/influx.conf "$INFLUX_REPO/influx.conf" && [ -s "$HOME/apps/tmp/influx.conf" ] || { echo "Error: Failed to download influx.conf or file is empty."; exit 1; }
  mv $HOME/apps/tmp/influx.conf $INFLUX_HOME/data/influxdbv2/influx.conf
  curl -fsSL -o $HOME/apps/tmp/grafana.ini "$INFLUX_REPO/grafana.ini" && [ -s "$HOME/apps/tmp/grafana.ini" ] || { echo "Error: Failed to download grafana.ini or file is empty."; exit 1; }
  mv $HOME/apps/tmp/grafana.ini $GRF_HOME/conf/grafana.ini
  curl -fsSL -o $HOME/apps/tmp/ldap.toml "$INFLUX_REPO/ldap.toml" && [ -s "$HOME/apps/tmp/ldap.toml" ] || { echo "Error: Failed to download ldap.toml or file is empty."; exit 1; }
  mv $HOME/apps/tmp/ldap.toml $GRF_HOME/conf/ldap.toml
  curl -fsSL -o $HOME/apps/tmp/telegraf.conf "$INFLUX_REPO/telegraf.conf" && [ -s "$HOME/apps/tmp/telegraf.conf" ] || { echo "Error: Failed to download telegraf.conf or file is empty."; exit 1; }
  mv $HOME/apps/tmp/telegraf.conf $TELEGRAF_HOME/etc/telegraf/telegraf.conf
  echo "InfluxDB deployment completed."
}

kafka_deploy() {
  #Kafka deployment requires Auth token to access private repo
  echo "Starting Kafka deployment..."
  KAFKA_REPO="$GIT_BASE_URL/kafka-setup/refs/heads/main"
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/server.properties "$KAFKA_REPO/server.properties" && [ -s "$HOME/apps/tmp/server.properties" ] || { echo "Error: Failed to download server.properties or file is empty."; exit 1; }
  mv $HOME/apps/tmp/server.properties $KAFKA_HOME/config/server.properties
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/ssl-client.properties "$KAFKA_REPO/ssl-client.properties" && [ -s "$HOME/apps/tmp/ssl-client.properties" ] || { echo "Error: Failed to download ssl-client.properties or file is empty."; exit 1; }
  mv $HOME/apps/tmp/ssl-client.properties $KAFKA_HOME/config/ssl-client.properties\
  #Publisher deployment
  #bin files
  mkdir -p $HOME/apps/tmp/publisher/bin
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/publisher/bin/.env "$KAFKA_REPO/publisher/bin/.env" && [ -s "$HOME/apps/tmp/publisher/bin/.env" ] || { echo "Error: Failed to download .env or file is empty."; exit 1; }
  mv $HOME/apps/tmp/publisher/bin/.env $HOME/apps/kafka/publisher/bin/.env
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/publisher/bin/publish.py "$KAFKA_REPO/publisher/bin/publish.py" && [ -s "$HOME/apps/tmp/publisher/bin/publish.py" ] || { echo "Error: Failed to download publish.py or file is empty."; exit 1; }
  mv $HOME/apps/tmp/publisher/bin/publish.py $HOME/apps/kafka/publisher/bin/publish.py
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/publisher/bin/requirements.txt "$KAFKA_REPO/publisher/bin/requirements.txt" && [ -s "$HOME/apps/tmp/publisher/bin/requirements.txt" ] || { echo "Error: Failed to download requirements.txt or file is empty."; exit 1; }
  mv $HOME/apps/tmp/publisher/bin/requirements.txt $HOME/apps/kafka/publisher/bin/requirements.txt
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/publisher/bin/start.sh "$KAFKA_REPO/publisher/bin/start.sh" && [ -s "$HOME/apps/tmp/publisher/bin/start.sh" ] || { echo "Error: Failed to download start.sh or file is empty."; exit 1; }
  mv $HOME/apps/tmp/publisher/bin/start.sh $HOME/apps/kafka/publisher/bin/start.sh
  chmod +x $HOME/apps/kafka/publisher/bin/start.sh
  #config files
  mkdir -p $HOME/apps/tmp/publisher/config
  for i in {1..40}; do
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o $HOME/apps/tmp/publisher/config/dev${i}_config_update.json "$KAFKA_REPO/publisher/config/dev${i}_config_update.json" && [ -s "$HOME/apps/tmp/publisher/config/dev${i}_config_update.json" ] || { echo "Error: Failed to download dev${i}_config_update.json or file is empty."; exit 1; }
    mv $HOME/apps/tmp/publisher/config/dev${i}_config_update.json $HOME/apps/kafka/publisher/config/dev${i}_config_update.json
  done
  echo "Kafka deployment completed."
}

mysql_deploy() {
  echo "Starting MySQL deployment..."
  MSQL_REPO="$GIT_BASE_URL/mysql-setup/refs/heads/main"
  #DB1
  mkdir -p $HOME/apps/tmp/db1
  curl -fsSL -o $HOME/apps/tmp/db1/my.cnf "$MSQL_REPO/db1/my.cnf" && [ -s "$HOME/apps/tmp/db1/my.cnf" ] || { echo "Error: Failed to download my.cnf for DB1 or file is empty."; exit 1; }
  mv $HOME/apps/tmp/db1/my.cnf $MSQL_DB1_HOME/config/my.cnf
  curl -fsSL -o $HOME/apps/tmp/db1/start.sh "$MSQL_REPO/db1/start.sh" && [ -s "$HOME/apps/tmp/db1/start.sh" ] || { echo "Error: Failed to download start.sh for DB1 or file is empty."; exit 1; }
  mv $HOME/apps/tmp/db1/start.sh $MSQL_HOME/db1/bin/start.sh
  chmod +x $MSQL_HOME/db1/bin/start.sh
  #DB2
  mkdir -p $HOME/apps/tmp/db2
  curl -fsSL -o $HOME/apps/tmp/db2/my.cnf "$MSQL_REPO/db2/my.cnf" && [ -s "$HOME/apps/tmp/db2/my.cnf" ] || { echo "Error: Failed to download my.cnf for DB2 or file is empty."; exit 1; }
  mv $HOME/apps/tmp/db2/my.cnf $MSQL_DB2_HOME/config/my.cnf
  curl -fsSL -o $HOME/apps/tmp/db2/start.sh "$MSQL_REPO/db2/start.sh" && [ -s "$HOME/apps/tmp/db2/start.sh" ] || { echo "Error: Failed to download start.sh for DB2 or file is empty."; exit 1; }
  mv $HOME/apps/tmp/db2/start.sh $MSQL_HOME/db2/bin/start.sh
  chmod +x $MSQL_HOME/db2/bin/start.sh
  echo "MySQL deployment completed."
}

neo4j_deploy() {
  echo "Starting Neo4j deployment..."
  NEO4J_REPO="$GIT_BASE_URL/neo4j-setup/refs/heads/main"
  #env file of graphrag application
  curl -fsSL -o $HOME/apps/tmp/.env "$NEO4J_REPO/.env" && [ -s "$HOME/apps/tmp/.env" ] || { echo "Error: Failed to download .env or file is empty."; exit 1; }
  #retrieve passwords from secrets file and update .env
  retrieve_pw "$SECRETS_DIR/openai_token" "$HOME/apps/tmp/.env" "openai_api_placeholder" "openai_token" "="
  retrieve_pw "$SECRETS_DIR/neo4j" "$HOME/apps/tmp/.env" "neo4j_password_placeholder" "neo4j-password" ":" 
  echo "Passwords retrieved and .env file updated."
  cat $HOME/apps/tmp/.env
  #move edited .env to neo4j conf directory
  mv $HOME/apps/tmp/.env $NEO4J_HOME/../bin/.env
  #graphrag application deployment
  curl -fsSL -o $HOME/apps/tmp/knowledge_ingest.py "$NEO4J_REPO/knowledge_ingest.py" && [ -s "$HOME/apps/tmp/knowledge_ingest.py" ] || { echo "Error: Failed to download knowledge_ingest.py or file is empty."; exit 1; }
  curl -fsSL -o $HOME/apps/tmp/knowledge_query.py "$NEO4J_REPO/knowledge_query.py" && [ -s "$HOME/apps/tmp/knowledge_query.py" ] || { echo "Error: Failed to download knowledge_query.py or file is empty."; exit 1; }
  curl -fsSL -o $HOME/apps/tmp/requirements.txt "$NEO4J_REPO/requirements.txt" && [ -s "$HOME/apps/tmp/requirements.txt" ] || { echo "Error: Failed to download requirements.txt or file is empty."; exit 1; }
  curl -fsSL -o $HOME/apps/tmp/start.sh "$NEO4J_REPO/start.sh" && [ -s "$HOME/apps/tmp/start.sh" ] || { echo "Error: Failed to download start.sh or file is empty."; exit 1; }
  mv $HOME/apps/tmp/start.sh $NEO4J_HOME/../bin/start.sh
  mv $HOME/apps/tmp/requirements.txt $NEO4J_HOME/../bin/requirements.txt
  mv $HOME/apps/tmp/knowledge_ingest.py $NEO4J_HOME/../bin/knowledge_ingest.py
  mv $HOME/apps/tmp/knowledge_query.py $NEO4J_HOME/../bin/knowledge_query.py
  chmod +x $NEO4J_HOME/../bin/start.sh
  chmod +x $NEO4J_HOME/../bin/knowledge_ingest.py
  chmod +x $NEO4J_HOME/../bin/knowledge_query.py
  echo "Graphrag application deployment completed."
  #neo4j.conf deployment
  curl -fsSL -o $HOME/apps/tmp/neo4j.conf "$NEO4J_REPO/neo4j.conf" && [ -s "$HOME/apps/tmp/neo4j.conf" ] || { echo "Error: Failed to download neo4j.conf or file is empty."; exit 1; }
  mv $HOME/apps/tmp/neo4j.conf $NEO4J_HOME/conf/neo4j.conf
  echo "neo4j.conf deployed."
  echo "Neo4j deployment completed."
}

rabbitmq_deploy() {
  echo "Starting RabbitMQ deployment..."
  #deploy rabbitmq.conf
  RABBITMQ_REPO="$GIT_BASE_URL/rabbitmq-setup/refs/heads/main"
  curl -fsSL -o $HOME/apps/tmp/rabbitmq.conf "$RABBITMQ_REPO/rabbitmq.conf" && [ -s "$HOME/apps/tmp/rabbitmq.conf" ] || { echo "Error: Failed to download rabbitmq.conf or file is empty."; exit 1; }
  #retrieve passwords from secrets file and update rabbitmq.conf
  retrieve_pw "$SECRETS_DIR/rabbitmq_cred" "$HOME/apps/tmp/rabbitmq.conf" "rabbitmq_password" "rabbitmq_password_placeholder" "="
  mv $HOME/apps/tmp/rabbitmq.conf $RABBITMQ_HOME/etc/rabbitmq/rabbitmq.conf
  echo "RabbitMQ deployment completed."
}

load_generator_deploy() {
  echo "Starting Load-Generator deployment..."
  LOAD_GEN_REPO="$GIT_BASE_URL/load-generator/refs/heads/main"
  #.env properties
  curl -fsSL -o $HOME/apps/tmp/.env "$LOAD_GEN_REPO/.env" && [ -s "$HOME/apps/tmp/.env" ] || { echo "Error: Failed to download .env or file is empty."; exit 1; }
  #retrieve passwords from secrets file and update .env
  retrieve_pw "$SECRETS_DIR/rabbitmq_cred" "$HOME/apps/tmp/.env" "rabbitmq_password" "rabbitmq_password_placeholder" "="
  retrieve_pw "$SECRETS_DIR/hmac_key" "$HOME/apps/tmp/.env" "hmac_key" "hmac_key_placeholder" "="
  retrieve_pw "$SECRETS_DIR/db_cred" "$HOME/apps/tmp/.env" "daddy" "mysql_password_placeholder" ":"
  mv $HOME/apps/tmp/.env $LOAD_GEN_HOME/bin/.env
  #requirements file
  curl -fsSL -o $HOME/apps/tmp/requirements.txt "$LOAD_GEN_REPO/requirements.txt" && [ -s "$HOME/apps/tmp/requirements.txt" ] || { echo "Error: Failed to download requirements.txt or file is empty."; exit 1; }
  mv $HOME/apps/tmp/requirements.txt $LOAD_GEN_HOME/bin/requirements.txt
  #bin files
  curl -fsSL -o $HOME/apps/tmp/start.sh "$LOAD_GEN_REPO/start.sh" && [ -s "$HOME/apps/tmp/start.sh" ] || { echo "Error: Failed to download start.sh or file is empty."; exit 1; }
  mv $HOME/apps/tmp/start.sh $LOAD_GEN_HOME/bin/start.sh
  chmod +x $LOAD_GEN_HOME/bin/start.sh
  curl -fsSL -o $HOME/apps/tmp/source-data-interface.py "$LOAD_GEN_REPO/source-data-interface.py" && [ -s "$HOME/apps/tmp/source-data-interface.py" ] || { echo "Error: Failed to download source-data-interface.py or file is empty."; exit 1; }
  mv $HOME/apps/tmp/source-data-interface.py $LOAD_GEN_HOME/bin/source-data-interface.py
  chmod +x $LOAD_GEN_HOME/bin/source-data-interface.py
  curl -fsSL -o $HOME/apps/tmp/passenger-svc.py "$LOAD_GEN_REPO/passenger-svc.py" && [ -s "$HOME/apps/tmp/passenger-svc.py" ] || { echo "Error: Failed to download passenger-svc.py or file is empty."; exit 1; }
  mv $HOME/apps/tmp/passenger-svc.py $LOAD_GEN_HOME/bin/passenger-svc.py
  chmod +x $LOAD_GEN_HOME/bin/passenger-svc.py
  echo "Load-Generator deployment completed."
}

#cleanup
cleanup() {
  #cleanup old backups
  BACKUP_PATH="$HOME/apps/backups/${APPLICATION_NAME}/"
  cd "$BACKUP_PATH" || { echo "Error: Cannot access backup directory."; exit 1; }
  BACKUP_VERSIONS=($(ls -t .))
  COUNT=${#BACKUP_VERSIONS[@]}  
  if [ $COUNT -gt $RETENTION_CYCLES ]; then
    echo "Cleaning up old backups..."
    for ((i=RETENTION_CYCLES; i<COUNT; i++)); do
      rm -rf "${BACKUP_VERSIONS[i]}"
    done
  fi
  #cleanup temp files
  echo "Cleaning up temporary files..."
  rm -rf $HOME/apps/tmp/*
}

#Main Deployment Logic 
#influxdb deployment with backup and rollback
if [ "$APPLICATION_NAME" == "influxdb" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup InfluxDB..."
  influxdb_backup
  echo "Deploying InfluxDB..."
  influxdb_deploy
elif [ "$APPLICATION_NAME" == "influxdb" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back InfluxDB..."
  influxdb_rollback
#kafka deployment with backup and rollback
elif [ "$APPLICATION_NAME" == "kafka" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup Kafka..."
  kafka_backup
  echo "Deploying Kafka..."
  kafka_deploy
elif [ "$APPLICATION_NAME" == "kafka" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Kafka..."
  kafka_rollback
elif [ "$APPLICATION_NAME" == "infra" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Infra..."
elif [ "$APPLICATION_NAME" == "infra" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Infra..."
elif [ "$APPLICATION_NAME" == "msql" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup MySQL..."
  msql_backup
  echo "Deploying MySQL..."
  mysql_deploy
elif [ "$APPLICATION_NAME" == "msql" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back MySQL..."
  mysql_rollback
elif [ "$APPLICATION_NAME" == "neo4j" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup Neo4j..."
  neo4j_backup
  echo "Deploying Neo4j..."
  neo4j_deploy
elif [ "$APPLICATION_NAME" == "neo4j" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Neo4j..."
  neo4j_rollback
elif [ "$APPLICATION_NAME" == "ollama" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Ollama..."
elif [ "$APPLICATION_NAME" == "ollama" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Ollama..." 
elif [ "$APPLICATION_NAME" == "opensearch" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying OpenSearch..."
elif [ "$APPLICATION_NAME" == "opensearch" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back OpenSearch..."
elif [ "$APPLICATION_NAME" == "rabbitmq" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup RabbitMQ..."
  rabbitmq_backup
  echo "Deploying RabbitMQ..."
  rabbitmq_deploy
elif [ "$APPLICATION_NAME" == "rabbitmq" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back RabbitMQ..."
elif [ "$APPLICATION_NAME" == "zookeeper" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Zookeeper..."
elif [ "$APPLICATION_NAME" == "zookeeper" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Zookeeper..."
elif [ "$APPLICATION_NAME" == "load-generator" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Backup Load-Generator..."
  load_generator_backup
  echo "Deploying load-generator..."
  load_generator_deploy
elif [ "$APPLICATION_NAME" == "load-generator" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back load-generator..."
  load_generator_rollback
else
  echo "Error: Deployment logic for $APPLICATION_NAME is not implemented."
  exit 1
fi
cleanup
echo "Deployment script completed successfully."