FROM python:3.9-slim-buster

ARG GIT_SHA
ARG BUILD_DATE
ARG TRIVY_VERSION=0.30.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      wget \
      ca-certificates \
      tar \
 && rm -rf /var/lib/apt/lists/*


RUN wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
 && tar zxvf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
 && mv trivy /usr/local/bin/ \
 && rm trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz

WORKDIR /app


COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ENV GIT_SHA=$GIT_SHA
ENV BUILD_DATE=$BUILD_DATE

COPY . .


RUN groupadd --gid 1000 appuser \
 && useradd --uid 1000 --gid appuser --shell /bin/bash --create-home appuser
USER appuser



EXPOSE 5000
CMD ["flask", "run", "--host=0.0.0.0"]
