import os
import csv
import json
import time
import ssl
import random
import pika
import logging
import sys
from data_lake import sample_lake
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

def bootstrap():
    #Environment variables
    global tmp_dir, ca_cert, rmq_url, rmq_port, rmq_username, rmq_password, interval, QUEUE_NAME, PUBLISH_INTERVAL, n_flights, n_passengers, logdir, loglvl, logger, log_level, formatter, stdout_handler, file_handler, meter, publish_exec_time
    tmp_dir = os.getenv("TMP_DIR")
    ca_cert= os.environ.get("CA_PATH")
    rmq_url = os.environ.get("RMQ_HOST")
    rmq_port = int(os.environ.get("RMQ_PORT"))
    rmq_username = os.environ.get("RMQ_USER")
    rmq_password = os.environ.get("RMQ_PW")
    QUEUE_NAME = "source_data_intake"
    PUBLISH_INTERVAL = int(os.environ.get("INT_PERIOD"))
    logdir = os.environ.get("log_directory", ".")
    loglvl = os.environ.get("log_level", "INFO").upper()
    n_flights= int(os.environ.get("no_flights_per_cycle", "10"))
    n_passengers= int(os.environ.get("no_passengers_per_flight", "50"))
    otel_service_name = "source-data-interface"
    otel_exporter_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    otel_exporter_interval = int(os.environ.get("OTEL_EXPORT_INTERVAL"))
    release_version = os.environ.get("release_version")

    #logging 
    log_level = getattr(logging, loglvl, logging.INFO)
    logger = logging.getLogger()
    logger.setLevel(log_level)
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setLevel(log_level)
    stdout_handler.setFormatter(formatter)

    file_handler = logging.FileHandler(f'{logdir}/source-data-interface.log')
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
    publish_exec_time = meter.create_histogram(
        "application.execution_time",
        unit="ms",
        description="Time spent unpackaging message, publishing to RMQ"
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


def load_csv():
    with open(f"{tmp_dir}/batch_payload.csv", newline="", encoding="utf-8") as csvfile:
        return list(csv.DictReader(csvfile))


def main():
    bootstrap()
    logger.info("**********Starting source data publisher**********")
    logger.info(f"Connecting to RabbitMQ at {rmq_url}:{rmq_port}")
    connection = get_rmq_connection()
    channel = connection.channel()
    logger.info(f"Declaring queue {QUEUE_NAME}")
    channel.queue_declare(queue=QUEUE_NAME, durable=True)
    try:
        while True:
            logger.info(f"Loading payloads from {tmp_dir}/batch_payload.csv")
            sample_lake()
            rows = load_csv()
            logger.info(f"Loaded {len(rows)} rows")
            for n in range(n_flights * n_passengers):
                start = time.perf_counter()
                logger.info("Publishing new message from source data")
                row = random.choice(rows)
                rows.remove(row)

                message = {
                    "passenger_id": row["Passenger ID"],
                    "first_name": row["First Name"],
                    "last_name": row["Last Name"],
                    "age": int(row["Age"]),
                    "nationality": row["Nationality"],
                    "departure_date": row["Departure Date"],
                    "arrival_airport": row["Arrival Airport"],
                    "flight_status": row["Flight Status"],
                    "ingested_at": int(time.time())
                }

                body = json.dumps(message)
                logger.debug(f"Publishing message: {body}")

                channel.basic_publish(
                    exchange="",
                    routing_key=QUEUE_NAME,
                    body=body,
                    properties=pika.BasicProperties(
                        delivery_mode=2
                    )
                )

                logger.info(f"Published random passenger {message['passenger_id']}")

                with open(f"{tmp_dir}/ingested.jsonl", "a") as f: 
                    f.write(json.dumps(row) + "\n")

                duration_ms = (time.perf_counter() - start) * 1000
                publish_exec_time.record(duration_ms)
                
                time.sleep(PUBLISH_INTERVAL)
    except KeyboardInterrupt:
        logger.info("Shutting down publisher")
    finally:
        connection.close()

if __name__ == "__main__":
    main()
