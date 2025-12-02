FROM python:3.14-slim

WORKDIR /app

RUN pip install flask

COPY deepeval_service.py .

EXPOSE 8080

CMD ["python", "deepeval_service.py"]