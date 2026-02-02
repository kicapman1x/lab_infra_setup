FROM python:3.11-slim

WORKDIR /app/load-generator

RUN apt-get update && apt-get install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY passenger-svc.py ./

ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "-u", "passenger-svc.py"]