FROM python:3.11-slim

WORKDIR /app

RUN pip install flask

COPY deepeval_service.py .

EXPOSE 8080

CMD ["python", "deepeval_service.py"]