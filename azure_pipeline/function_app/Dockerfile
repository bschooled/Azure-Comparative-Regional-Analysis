FROM mcr.microsoft.com/azure-functions/python:4-python3.12@sha256:b11f9dcf1450c1f2cb0c8a8be19cfbf41803722c4c869315342d78ca797527ae

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