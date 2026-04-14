FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System deps (certs, curl for health checks, libxml libs Scrapy likes)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy project metadata and install deps first (better layer caching)
COPY pyproject.toml ./
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
 && pip install --no-cache-dir .

# Then copy source
COPY scrapy.cfg run.py ./ 
COPY crawler ./crawler
COPY extractor ./extractor

# Create a data mount point
VOLUME ["/data"]

# Default environment
ENV MAX_DEPTH=3 OUTPUT=/data/out.jsonl

# Entrypoint uses run.py; pass args with `podman run ... -- --start-url=...`
ENTRYPOINT ["python", "/app/run.py"]
