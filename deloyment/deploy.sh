#!/bin/bash
#Deployment script for homelab

#Applications tracked
VALID_APPLICATIONS=("influxdb" "kafka" "infra" "msql" "neo4j" "ollama" "opensearch" "rabbitmq" "zookeeper")
VALID_DEPLOYMENT_ACTIONS=("deploy" "rollback")
VERSION=uuidgen
GIT_BASE_URL="https://raw.githubusercontent.com/kicapman1x"

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

# Validate parameters
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

#Rollback 
influxdb_rollback() {
  echo "Rolling back InfluxDB to previous version..."
  VERSION_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$ROLLBACK_VERSION"
  cp -r "$VERSION_DIR/influx.conf" "$INFLUX_HOME/data/influxdbv2/"
  cp -r "$VERSION_DIR/grafana.ini" "$GRF_HOME/conf/"
  cp -r "$VERSION_DIR/ldap.toml" "$GRF_HOME/conf/"
  echo "InfluxDB rollback to version $ROLLBACK_VERSION completed."
}

#Back up existing deployment if it exists
influxdb_backup() {
  BACKUP_DIR="$HOME/apps/backups/${APPLICATION_NAME}/$VERSION"
  mkdir -rp "$BACKUP_DIR"
  cp -r "$INFLUX_HOME/data/influxdbv2/influx.conf" "$BACKUP_DIR/"
  cp -r "$GRF_HOME/conf/grafana.ini" "$BACKUP_DIR/"
  cp -r "$GRF_HOME/conf/ldap.toml" "$BACKUP_DIR/"
  cp -r "$TELEGRAF_HOME/etc/telegraf/telegraf.conf" "$BACKUP_DIR/"
  echo "Backup of $APPLICATION_NAME completed at $BACKUP_DIR"
}

#Deploy InfluxDB
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
  echo "Deploying Kafka..."
elif [ "$APPLICATION_NAME" == "kafka" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Kafka..."
elif [ "$APPLICATION_NAME" == "infra" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Infra..."
elif [ "$APPLICATION_NAME" == "infra" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Infra..."
elif [ "$APPLICATION_NAME" == "msql" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying MySQL..."
elif [ "$APPLICATION_NAME" == "msql" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back MySQL..."
elif [ "$APPLICATION_NAME" == "neo4j" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Neo4j..."
elif [ "$APPLICATION_NAME" == "neo4j" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Neo4j..."
elif [ "$APPLICATION_NAME" == "ollama" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Ollama..."
elif [ "$APPLICATION_NAME" == "ollama" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Ollama..." 
elif [ "$APPLICATION_NAME" == "opensearch" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying OpenSearch..."
elif [ "$APPLICATION_NAME" == "opensearch" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back OpenSearch..."
elif [ "$APPLICATION_NAME" == "rabbitmq" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying RabbitMQ..."
elif [ "$APPLICATION_NAME" == "rabbitmq" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back RabbitMQ..."
elif [ "$APPLICATION_NAME" == "zookeeper" ] && [ "$DEPLOY_ROLLBACK" == "deploy" ]; then
  echo "Deploying Zookeeper..."
elif [ "$APPLICATION_NAME" == "zookeeper" ] && [ "$DEPLOY_ROLLBACK" == "rollback" ]; then
  echo "Rolling back Zookeeper..."
else
  echo "Error: Deployment logic for $APPLICATION_NAME is not implemented."
  exit 1
fi