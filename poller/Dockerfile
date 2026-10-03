FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY ecobici_poller ./ecobici_poller
USER nobody
# One worker: a poll is a few hundred milliseconds of I/O once a minute.
CMD exec gunicorn --bind ":${PORT:-8080}" --workers 1 --threads 4 --timeout 60 --no-control-socket "ecobici_poller.app:create_app_from_env()"
