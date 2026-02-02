FROM python:3.11-slim

WORKDIR /app/load-generator

RUN apt-get update && apt-get install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt

COPY data_lake.py source-data-interface.py ./

ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "-u", "source-data-interface.py"]