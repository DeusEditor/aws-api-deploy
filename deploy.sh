#!/bin/bash

echo -e '\033[42m[Run->]\033[0m Get config data'
HOST=$(aws ssm get-parameters --name HOST --region eu-central-1 --output text --query Parameters[].Value)
HOST_API=$(aws ssm get-parameters --name HOST_API --region eu-central-1 --output text --query Parameters[].Value)
DB_USER=$(aws ssm get-parameters --name DB_USER --region eu-central-1 --output text --query Parameters[].Value)
DB_NAME=$(aws ssm get-parameters --name DB_NAME --region eu-central-1 --output text --query Parameters[].Value)
DB_HOST=$(aws ssm get-parameters --name DB_HOST --region eu-central-1 --output text --query Parameters[].Value)
DB_PASSWORD=$(aws ssm get-parameters --name DB_PASSWORD --region eu-central-1 --with-decryption --output text --query Parameters[].Value)
SMTP_USER=$(aws ssm get-parameters --name SMTP_USER --region eu-central-1 --output text --query Parameters[].Value)
SMTP_HOST=$(aws ssm get-parameters --name SMTP_HOST --region eu-central-1 --output text --query Parameters[].Value)
SMTP_PASSWORD=$(aws ssm get-parameters --name SMTP_PASSWORD --region eu-central-1 --with-decryption --output text --query Parameters[].Value)
MESSENGER_ACCESS_KEY=$(aws ssm get-parameters --name MESSENGER_ACCESS_KEY --region eu-central-1 --output text --query Parameters[].Value)
MESSENGER_URL=$(aws ssm get-parameters --name MESSENGER_URL --region eu-central-1 --output text --query Parameters[].Value)
MESSENGER_SECRET_KEY=$(aws ssm get-parameters --name MESSENGER_SECRET_KEY --region eu-central-1 --with-decryption --output text --query Parameters[].Value)
JWT_PASSPHRASE=$(aws ssm get-parameters --name JWT_PASSPHRASE --region eu-central-1 --with-decryption --output text --query Parameters[].Value)
AWS_ACCESS_KEY_ID=$(aws ssm get-parameters --name _AWS_ACCESS_KEY_ID --region eu-central-1 --output text --query Parameters[].Value)
AWS_SECRET_ACCESS_KEY=$(aws ssm get-parameters --name _AWS_SECRET_ACCESS_KEY --region eu-central-1 --with-decryption --output text --query Parameters[].Value)
WEBSOCKET_PORT=$(aws ssm get-parameters --name WEBSOCKET_PORT --region eu-central-1 --output text --query Parameters[].Value)
S3_BUCKET_NAME=$(aws ssm get-parameters --name S3_BUCKET_NAME --region eu-central-1 --output text --query Parameters[].Value)

MESSENGER_TRANSPORT_DSN=${MESSENGER_URL}?access_key=${MESSENGER_ACCESS_KEY}"&"secret_key=${MESSENGER_SECRET_KEY}
DATABASE_URL=mysql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
MAILER_DSN=smtp://${SMTP_USER}:${SMTP_PASSWORD}@${SMTP_HOST}
MAIN_SITE_URL=https://${HOST}
WEBSOCKET_URL=wss://${HOST_API}/ws
RESET_PASSWORD_URL=${MAIN_SITE_URL}/reset-password/

WORKDIR=/home/ec2-user

cd ${WORKDIR}

echo -e '\033[42m[Run->]\033[0m yum update'
yum update -y

echo -e '\033[42m[Run->]\033[0m Installing git'
yum install git -y

echo -e '\033[42m[Run->]\033[0m Installing docker'
amazon-linux-extras install docker -y
service docker start

ssh -o StrictHostKeyChecking=no git@github.com # allow git clone with accept rsa fingerprint

echo -e '\033[42m[Run->]\033[0m Clone docker'
git clone git@github.com:DeusEditor/docker-api.git

echo -e '\033[42m[Run->]\033[0m Clone api'
git clone git@github.com:DeusEditor/api.git

echo -e '\033[42m[Run->]\033[0m Installing app dependencies'
docker run --rm -v --interactive --tty --env DATABASE_URL --volume $WORKDIR/api:/app composer:2 install --ignore-platform-reqs

echo -e '\033[42m[Run->]\033[0m Building php image'
docker build -f $WORKDIR/docker-api/php/Dockerfile -t php_editor .

echo -e '\033[42m[Run->]\033[0m Building messenger image'
docker build -f $WORKDIR/docker-api/messenger/Dockerfile -t messenger_editor .

echo -e '\033[42m[Run->]\033[0m Building websocket image'
docker build -f $WORKDIR/docker-api/websocket/Dockerfile -t websocket_editor .

echo -e '\033[42m[Run->]\033[0m Building nginx image'
docker build \
  --build-arg HOST=$HOST \
  --build-arg WEBSOCKET_PASS=websocket_editor \
  --build-arg WEBSOCKET_PORT=$WEBSOCKET_PORT \
  --build-arg FASTCGI_PASS=php_editor \
  -f $WORKDIR/docker-api/nginx/Dockerfile \
  -t nginx_editor .

echo -e '\033[42m[Run->]\033[0m Create network'
docker network create editor

echo -e '\033[42m[Run->]\033[0m Run php container'
docker run -d \
    --network=editor \
    --restart=always \
    --env HOST=https://$HOST_API \
    --env DATABASE_URL=$DATABASE_URL \
    --env MESSENGER_TRANSPORT_DSN=$MESSENGER_TRANSPORT_DSN \
    --env MAILER_DSN=$MAILER_DSN \
    --env MAIN_SITE_URL=$MAIN_SITE_URL \
    --env WEBSOCKET_URL=$WEBSOCKET_URL \
    --env RESET_PASSWORD_URL=$RESET_PASSWORD_URL \
    --env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    --env AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    --env AWS_S3_BUCKET_NAME=S3_BUCKET_NAME \
    --env WEBSOCKET_PORT=$WEBSOCKET_PORT \
    --name php_editor php_editor

echo -e '\033[42m[Run->]\033[0m Run nginx container'
docker run -d --network=editor -p 80:80 --restart=always --name nginx_editor nginx_editor

echo -e '\033[42m[Run->]\033[0m Run messenger container'
docker run -d \
    --network=editor \
    --restart=always \
    --env DATABASE_URL=$DATABASE_URL \
    --env MESSENGER_TRANSPORT_DSN=$MESSENGER_TRANSPORT_DSN \
    --env MAILER_DSN=$MAILER_DSN \
    --env MAIN_SITE_URL=$MAIN_SITE_URL \
    --env WEBSOCKET_URL=$WEBSOCKET_URL \
    --env RESET_PASSWORD_URL=$RESET_PASSWORD_URL \
    --env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    --env AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    --env AWS_S3_BUCKET_NAME=S3_BUCKET_NAME \
    --env WEBSOCKET_PORT=$WEBSOCKET_PORT \
    messenger_editor php /var/www/html/bin/console messenger:consume async --time-limit=3600

echo -e '\033[42m[Run->]\033[0m Run websocket container'
docker run -d \
    --network=editor \
    --restart=always \
    --env DATABASE_URL=$DATABASE_URL \
    --env MESSENGER_TRANSPORT_DSN=$MESSENGER_TRANSPORT_DSN \
    --env MAILER_DSN=$MAILER_DSN \
    --env MAIN_SITE_URL=$MAIN_SITE_URL \
    --env WEBSOCKET_URL=$WEBSOCKET_URL \
    --env RESET_PASSWORD_URL=$RESET_PASSWORD_URL \
    --env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    --env AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    --env AWS_S3_BUCKET_NAME=S3_BUCKET_NAME \
    --env WEBSOCKET_PORT=$WEBSOCKET_PORT \
    --name websocket_editor \
    websocket_editor php /var/www/html/bin/console app:start-websocket
