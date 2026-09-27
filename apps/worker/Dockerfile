FROM python:3.12-slim
WORKDIR /app
COPY --chmod=644 requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chmod=644 worker.py .
USER nobody
CMD ["python", "-u", "worker.py"]
