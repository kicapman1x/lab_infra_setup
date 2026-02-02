import os
import csv
import json
import random
import time
from datetime import datetime, timedelta
import logging
import sys
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

def bootstrap():
    #Environment variables
    global payload_dir, tmp_dir, ca_cert, interval, n_flights, n_passengers, logdir, loglvl, output_file, logger, log_level, formatter, stdout_handler, file_handler, meter, publish_exec_time, logger, last_exec_time_ms
    payload_dir = os.getenv("PAYLOAD_DIR")
    tmp_dir = os.getenv("TMP_DIR")
    ca_cert= os.environ.get("CA_PATH")
    interval = int(os.environ.get("DATA_GENERATION_INTERVAL"))
    logdir = os.environ.get("log_directory", ".")
    loglvl = os.environ.get("log_level", "INFO").upper()
    n_flights= int(os.environ.get("no_flights_per_cycle", "10"))
    n_passengers= int(os.environ.get("no_passengers_per_flight", "50"))
    output_file = f"{tmp_dir}/batch_payload.csv"
    otel_service_name = "data-lake"
    otel_exporter_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    otel_exporter_interval = int(os.environ.get("OTEL_EXPORT_INTERVAL"))
    release_version = os.environ.get("release_version")
    last_exec_time_ms = 0.0 
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

    #FUTURE HAN TAKENOTE LEAVE THIS I WANT COMBINE LOGS SINCE ITS SAME CONTAINER
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
    def exec_time_callback(options):
        return [metrics.Observation(last_exec_time_ms)]

    publish_exec_time = meter.create_observable_gauge(
        "application.execution_time",
        unit="ms",
        description="Time spent unpackaging message, publishing to RMQ",
        callbacks=[exec_time_callback]
    )

def load_csv():
    with open(f"{payload_dir}/flights.csv", newline="", encoding="utf-8") as csvfile:
        return list(csv.DictReader(csvfile))


def sample_lake():
    bootstrap()
    logger.info("**********Starting source data publisher**********")
    logger.info("Deleting existing batch payload if any")
    global last_exec_time_ms
    start = time.perf_counter()
    if os.path.exists(output_file):
        os.remove(output_file)
        logger.info(f"Deleted existing file {output_file}")
    else:
        logger.info("No existing batch payload found")
    logger.info(f"Loading payloads from {payload_dir}/flights.csv")
    rows = load_csv()
    logger.info(f"Loaded {len(rows)} rows")

    header = [
        "Passenger ID", "First Name", "Last Name", "Gender", "Age",
        "Nationality", "Airport Name", "Airport Country Code", "Country Name",
        "Airport Continent", "Continents",
        "Departure Date", "Arrival Airport",
        "Pilot Name", "Flight Status"
    ]

    for i in range(n_flights):
        logger.info(f"Selecting {n_passengers} random rows")
        sampled_rows = random.sample(rows, n_passengers)

        ref_row = random.choice(sampled_rows)

        dt = datetime.now()
        dt += timedelta(
            hours=random.randint(1, 2),
            minutes=random.randint(0, 59)
        )
        uniform_departure_date = dt.strftime("%Y-%m-%d %H:%M")
        uniform_arrival_airport = ref_row["Arrival Airport"]

        logger.info(
            f"Normalized batch to departure_date={uniform_departure_date}, "
            f"arrival_airport={uniform_arrival_airport}"
        )

        for r in sampled_rows:
            rows.remove(r)
            r["Departure Date"] = uniform_departure_date
            r["Arrival Airport"] = uniform_arrival_airport

        file_exists = os.path.exists(output_file)

        with open(f"{tmp_dir}/batch_payload.csv", "a", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=header)

            if not file_exists:
                writer.writeheader() 
                file_exists = True

            writer.writerows(sampled_rows)

        logger.info(f"Wrote batch payload to {tmp_dir}/batch_payload.csv")
    duration_ms = (time.perf_counter() - start) * 1000
    last_exec_time_ms = duration_ms