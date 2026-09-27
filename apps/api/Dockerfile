FROM python:3.12-slim
WORKDIR /app
COPY --chmod=644 requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chmod=644 app.py .
USER nobody
EXPOSE 8080
CMD ["python", "-u", "app.py"]
