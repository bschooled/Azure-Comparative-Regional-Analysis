FROM mcr.microsoft.com/azure-functions/python:4-python3.12@sha256:852c8bb1914e740fcefb3141cfe017a9a9aaec3fe0d4844117119b7b89cc2c01

ARG PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    PIP_INDEX_URL=${PIP_INDEX_URL}

COPY requirements.txt /requirements.txt

RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir -r /requirements.txt

COPY . /home/site/wwwroot