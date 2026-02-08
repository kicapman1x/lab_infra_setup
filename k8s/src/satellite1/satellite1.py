import json
import ssl
import pika
import os
import hmac
import hashlib
import base64
import time
import mysql.connector
import uuid
import logging
import requests
import gzip
from datetime import datetime
import sys
from confluent_kafka import Consumer
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

def bootstrap():
    #Environment variables
    global facial_dir, facial_api, rmq_url, rmq_port, rmq_username, rmq_password, ca_cert, secret_key, mysql_url, mysql_port, mysql_user, mysql_password, CONSUME_TOPIC_NAME, logdir, loglvl, mysql_db_s1, logger, publish_exec_time, last_exec_time_ms, kafka_url, cert_file, key_file
    facial_dir = os.environ.get("FACIAL_DIR")
    facial_api = os.environ.get("image_gen_api")
    rmq_url = os.environ.get("RMQ_HOST")
    rmq_port = int(os.environ.get("RMQ_PORT"))
    rmq_username = os.environ.get("RMQ_USER")
    rmq_password = os.environ.get("RMQ_PW")
    kafka_url = os.environ.get("KAFKA_HOST")
    ca_cert = os.environ.get("CA_PATH")
    cert_file = os.environ.get("CERT_PATH")
    key_file = os.environ.get("KEY_PATH")
    secret_key = os.environ.get("HMAC_KEY").encode("utf-8")
    mysql_url = os.environ.get("MYSQL_HOST")
    mysql_port = int(os.environ.get("MYSQL_PORT"))
    mysql_user = os.environ.get("MYSQL_USER")
    mysql_password = os.environ.get("MYSQL_PW")
    mysql_db_s1 = os.environ.get("MYSQL_DB_SATELLITE1")
    CONSUME_TOPIC_NAME = "ingest_facial_data_s1"
    logdir = os.environ.get("log_directory", ".")
    loglvl = os.environ.get("log_level", "INFO").upper()
    otel_service_name = "satellite1"
    otel_exporter_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    otel_exporter_interval = int(os.environ.get("OTEL_EXPORT_INTERVAL"))
    release_version = os.environ.get("release_version")
    last_exec_time_ms = 0.0

    #Logging setup
    log_level = getattr(logging, loglvl, logging.INFO)
    logger = logging.getLogger()
    logger.setLevel(log_level)
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setLevel(log_level)
    stdout_handler.setFormatter(formatter)

    file_handler = logging.FileHandler(f'{logdir}/satellite1.log')
    file_handler.setLevel(log_level)
    file_handler.setFormatter(formatter)

    logger.addHandler(stdout_handler)
    logger.addHandler(file_handler)

    #OTEL setup
    resource = Resource.create({
        "service.name": otel_service_name,
        "service.version": release_version,
    })

    metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(endpoint=otel_exporter_endpoint, insecure=True),
    export_interval_millis=otel_exporter_interval
    )

    metrics.set_meter_provider(
        MeterProvider(
            resource=resource,
            metric_readers=[metric_reader],
        )
    )

    meter = metrics.get_meter(__name__)

    #Different metrics 
    def exec_time_callback(options):
        return [metrics.Observation(last_exec_time_ms)]

    publish_exec_time = meter.create_observable_gauge(
        "application.execution_time",
        unit="ms",
        description="Time spent unpackaging message, publishing to RMQ",
        callbacks=[exec_time_callback]
    )

def get_kafka_consumer():
    conf = {
        'bootstrap.servers': kafka_url,
        'security.protocol': 'SSL',
        'ssl.ca.location': ca_cert,
        "ssl.certificate.location": cert_file,
        "ssl.key.location": key_file,
        'group.id': 'satellite1_group',
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': False,
        'max.poll.interval.ms': 300000
    }
    return Consumer(conf)

def get_mysql_connection_s1():
    return mysql.connector.connect(
        host=mysql_url,
        port=mysql_port,
        user=mysql_user,
        password=mysql_password,
        database=mysql_db_s1,

        ssl_ca=ca_cert,
        ssl_verify_cert=True,
        ssl_verify_identity=True,  

        autocommit=False
    )

def process_message(msg):
    global conn_s1, last_exec_time_ms
    conn_s1 = get_mysql_connection_s1()
    try:
        start = time.perf_counter()
        message = json.loads(msg.value().decode('utf-8'))
        logger.info("Received message for satellite 1")

        p_key = message["passenger_key"]
        trace_id = message["trace_id"]
        facial_image = message["facial_image"]
        departure_date = datetime.strptime(message["departure_date"], "%Y-%m-%d %H:%M")
        arrival_airport = message["arrival_airport"]
        logger.info(f"[{trace_id}] Inserting data for passenger: {p_key} with trace ID: {trace_id}")

        insert_full_data_satellite1(
            conn_s1,
            p_key,
            trace_id,
            facial_image,
            departure_date,
            arrival_airport
        )
        conn_s1.commit()
        logger.info(f"[{trace_id}] Successfully commited data for passenger: {p_key} into satellite 1 database.")
        duration_ms = (time.perf_counter() - start) * 1000
        last_exec_time_ms = duration_ms
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        raise
    finally:
        conn_s1.close()

def insert_full_data_satellite1(conn, passenger_key, trace_id, facial_image, departure_date, arrival_airport):
    cursor = conn.cursor()
    insert_query = """
        INSERT INTO touchpoint (passenger_key, trace_id, facial_image, departure_date, arrival_airport)
        VALUES (%s, %s, %s, %s, %s)
    """
    cursor.execute(insert_query, (passenger_key, trace_id, facial_image, departure_date, arrival_airport))
    logger.info(f"[{trace_id}] Inserted data for passenger {passenger_key} into satellite 1 database.")

def main():
    bootstrap()
    logger.info("**********Starting satellite1 service**********")

    logger.info("Starting SSL Kafka consumer...")
    global consumer
    consumer = get_kafka_consumer()
    consumer.subscribe([CONSUME_TOPIC_NAME])
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                logger.error(f"Consumer error: {msg.error()}")
                continue
            process_message(msg)
    except KeyboardInterrupt:
        logger.info("Shutting down satellite1 service")
    finally:
        consumer.close()

if __name__ == "__main__":
    main()