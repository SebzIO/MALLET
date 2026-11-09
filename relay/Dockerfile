# The MALLET relay (docs/RELAY.md). No dependencies: the standard library does everything.
FROM python:3.12-slim

WORKDIR /app
COPY relay.py .
RUN mkdir -p /data
VOLUME ["/data"]
EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8787/health', timeout=4)"

CMD ["python", "relay.py", "--host", "0.0.0.0", "--port", "8787", "--data-dir", "/data"]
