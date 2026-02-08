import json
import ssl
import pika
import os
import time
import sys
import hmac
import hashlib
import base64
import mysql.connector
import uuid
import logging
import gzip
from datetime import datetime
import random
from confluent_kafka import Producer
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

def bootstrap():
    #Environment variables
    global facial_dir, facial_api, rmq_url, rmq_port, rmq_username, rmq_password, ca_cert, secret_key, mysql_url, mysql_port, mysql_user, mysql_password, mysql_db, CONSUME_QUEUE_NAME, PRODUCE_TOPIC_NAME, logdir, loglvl, mysql_db_s1, mysql_db_s2, mysql_db_s3, logger, publish_exec_time, last_exec_time_ms, kafka_url, cert_file, key_file
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
    mysql_db = os.environ.get("MYSQL_DB")
    mysql_db_s1 = os.environ.get("MYSQL_DB_SATELLITE1")
    mysql_db_s2 = os.environ.get("MYSQL_DB_SATELLITE2")
    mysql_db_s3 = os.environ.get("MYSQL_DB_SATELLITE3")
    CONSUME_QUEUE_NAME = "upd_facial_data_flight"
    PRODUCE_TOPIC_NAME = "ingest_facial_data_"
    logdir = os.environ.get("log_directory", ".")
    loglvl = os.environ.get("log_level", "INFO").upper()
    otel_service_name = "satellite-interface"
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

    file_handler = logging.FileHandler(f'{logdir}/satellite-interface.log')
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

def get_rmq_connection():
    credentials = pika.PlainCredentials(
        rmq_username,
        rmq_password
    )

    ssl_context = ssl.create_default_context(cafile=ca_cert)
    ssl_context.check_hostname = True
    ssl_context.verify_mode = ssl.CERT_REQUIRED

    ssl_options = pika.SSLOptions(
        context=ssl_context,
        server_hostname=rmq_url
    )

    params = pika.ConnectionParameters(
        host=rmq_url,
        port=rmq_port,
        credentials=credentials,
        ssl_options=ssl_options,
        heartbeat=60,
        blocked_connection_timeout=30
    )

    return pika.BlockingConnection(params)

def get_kafka_producer():
    conf = {
        'bootstrap.servers': kafka_url,
        'security.protocol': 'SSL',
        'ssl.ca.location': ca_cert,
        "ssl.certificate.location": cert_file,
        "ssl.key.location": key_file
    }
    return Producer(conf)

def get_mysql_connection():
    return mysql.connector.connect(
        host=mysql_url,
        port=mysql_port,
        user=mysql_user,
        password=mysql_password,
        database=mysql_db,

        ssl_ca=ca_cert,
        ssl_verify_cert=True,
        ssl_verify_identity=True,  

        autocommit=False
    )

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

def get_mysql_connection_s2():
    return mysql.connector.connect(
        host=mysql_url,
        port=mysql_port,
        user=mysql_user,
        password=mysql_password,
        database=mysql_db_s2,

        ssl_ca=ca_cert,
        ssl_verify_cert=True,
        ssl_verify_identity=True,  

        autocommit=False
    )

def get_mysql_connection_s3():
    return mysql.connector.connect(
        host=mysql_url,
        port=mysql_port,
        user=mysql_user,
        password=mysql_password,
        database=mysql_db_s3,

        ssl_ca=ca_cert,
        ssl_verify_cert=True,
        ssl_verify_identity=True,  

        autocommit=False
    )

def process_message(channel, method, properties, body):
    global conn, conn_s1, conn_s2, conn_s3, last_exec_time_ms, kafka_producer_conn
    conn = get_mysql_connection()
    conn_s1 = get_mysql_connection_s1()
    conn_s2 = get_mysql_connection_s2()
    conn_s3 = get_mysql_connection_s3()
    kafka_producer_conn = get_kafka_producer()
    try:
        start = time.perf_counter()
        message = json.loads(body)
        logger.info("Received message")

        p_key = message["passenger_key"]
        trace_id = message["trace_id"]

        if passenger_exists_satellite(conn_s1, conn_s2, conn_s3, p_key):
            logger.warning(f"[{trace_id}] Passenger already exists : {p_key} - skipping ingesting to satellite queue.")
        else:
            selected_satellite = None
            departure_date = message["departure_date"]
            arrival_airport = message["arrival_airport"]
            satelite_check = flight_exists_satellite(conn_s1, conn_s2, conn_s3, datetime.strptime(departure_date,"%Y-%m-%d %H:%M"), arrival_airport)
            if satelite_check:
                selected_satellite = satelite_check
                logger.info(f"[{trace_id}] Flight exists in satellite {selected_satellite} - routing facial data accordingly.")
            else:
                selected_satellite = random.choice(["s1", "s2", "s3"])
                logger.info(f"[{trace_id}] Flight does not exist in any satellite - defaulting to randomly selected satellite {selected_satellite} for ingestion.")

            trace_id = message["trace_id"]
            logger.info(f"[{trace_id}] Ingesting data for passenger: {p_key} with trace ID: {trace_id}")

            logger.info(f"[{trace_id}] Publishing facial details to {PRODUCE_TOPIC_NAME}{selected_satellite}")
            message_push = {
                "passenger_key": message["passenger_key"],
                "trace_id": trace_id,
                "facial_image": message["facial_image"],
                "departure_date": departure_date,
                "arrival_airport": arrival_airport
            }
            body = json.dumps(message_push)
            kafka_producer_conn.produce(
                topic=PRODUCE_TOPIC_NAME + selected_satellite,
                value=body
            )
            kafka_producer_conn.flush()
            logger.info("Facial details written and message published.")
            duration_ms = (time.perf_counter() - start) * 1000
            last_exec_time_ms = duration_ms
        channel.basic_ack(delivery_tag=method.delivery_tag)   
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        channel.basic_nack(
            delivery_tag=method.delivery_tag,
            requeue=True
        )
    conn.close()

def passenger_exists_satellite_db(conn, passenger_key):
    logger.debug(f"Checking if passenger exists: {passenger_key}")
    cursor = conn.cursor()
    cursor.execute(
        "SELECT 1 FROM touchpoint WHERE passenger_key = %s LIMIT 1",
        (passenger_key,)
    )
    return cursor.fetchone() is not None

def passenger_exists_satellite(conn_s1, conn_s2, conn_s3, passenger_key):
    return (
        passenger_exists_satellite_db(conn_s1, passenger_key) or
        passenger_exists_satellite_db(conn_s2, passenger_key) or
        passenger_exists_satellite_db(conn_s3, passenger_key)
    )

def flight_exists_satellite_db(conn, departure_date, arrival_airport):
    logger.debug(f"Checking if flight exists: {departure_date} to {arrival_airport}")
    cursor = conn.cursor()
    cursor.execute(
        "SELECT 1 FROM touchpoint WHERE departure_date = %s AND arrival_airport = %s LIMIT 1",
        (departure_date, arrival_airport)
    )
    return cursor.fetchone() is not None

def flight_exists_satellite(conn_s1, conn_s2, conn_s3, departure_date, arrival_airport):
    if flight_exists_satellite_db(conn_s1, departure_date, arrival_airport):
        return "s1"
    elif flight_exists_satellite_db(conn_s2, departure_date, arrival_airport):
        return "s2"
    elif flight_exists_satellite_db(conn_s3, departure_date, arrival_airport):
        return "s3"
    else:
        return None

def main():
    bootstrap()
    logger.info("**********Starting satellite-interface service**********")

    logger.info("Starting SSL RabbitMQ consumer...")
    global connection, channel 
    connection = get_rmq_connection()
    channel = connection.channel()

    logger.info(f"Declaring queue {CONSUME_QUEUE_NAME}")
    channel.queue_declare(queue=CONSUME_QUEUE_NAME, durable=True)
    channel.basic_qos(prefetch_count=1)

    logger.info(f"Consuming messages from {CONSUME_QUEUE_NAME}")
    channel.basic_consume(
        queue=CONSUME_QUEUE_NAME,
        on_message_callback=process_message,
        auto_ack=False
    )

    try:
        logger.info("Waiting for messages. Ctrl+C to exit.")
        channel.start_consuming()

    except KeyboardInterrupt:
        logger.info("Stopping consumer...")
    finally:
        channel.stop_consuming()
        connection.close()


if __name__ == "__main__":
    main()