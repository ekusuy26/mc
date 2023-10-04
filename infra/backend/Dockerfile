FROM python:3.9

RUN apt-get update

RUN mkdir -p /root/src

COPY ./infra/backend/requirements.txt /root/src
WORKDIR /root/src

RUN pip install --upgrade pip
RUN pip install -r requirements.txt

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "80","--reload"]