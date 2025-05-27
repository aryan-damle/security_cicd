FROM python:3.11-slim
WORKDIR /app


COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt


COPY . .


RUN groupadd --gid 1000 appuser \
 && useradd --uid 1000 --gid appuser --shell /bin/bash --create-home appuser
USER appuser

EXPOSE 5000
CMD ["flask", "run", "--host=0.0.0.0"]
