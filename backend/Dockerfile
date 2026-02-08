FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app app
COPY migrations migrations

ENV PYTHONUNBUFFERED=1
ENV PORT=8000

CMD ["uvicorn", "app.main:app", "--host=0.0.0.0", "--port=8000", "--workers=1"]
