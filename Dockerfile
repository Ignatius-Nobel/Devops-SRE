# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.12

# ---- builder: resolve dependencies into an isolated prefix ----
FROM python:${PYTHON_VERSION}-alpine AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime: minimal, non-root, no package manager ----
FROM python:${PYTHON_VERSION}-alpine
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_PORT=8080

# Remove pip/setuptools/wheel (smaller image, smaller attack surface, fewer CVEs)
RUN python -m pip uninstall -y pip setuptools wheel >/dev/null 2>&1 || true \
 && addgroup -S -g 10001 app \
 && adduser -S -D -H -u 10001 -G app -s /sbin/nologin app

COPY --from=builder /install /usr/local
WORKDIR /app
COPY --chown=10001:10001 app/ /app/

USER 10001:10001
EXPOSE 8080
CMD ["python", "main.py"]
