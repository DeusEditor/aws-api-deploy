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
WEBSOCKET_PASS=$(aws ssm get-parameters --name FFMPEG_SERVER_IP --region eu-central-1 --output text --query Parameters[].Value)
S3_BUCKET_NAME=$(aws ssm get-parameters --name S3_BUCKET_NAME --region eu-central-1 --output text --query Parameters[].Value)
FONDY_SECRET_KEY=$(aws ssm get-parameters --name FONDY_SECRET_KEY --region eu-central-1 --with-decryption --output text --query Parameters[].Value)

MESSENGER_TRANSPORT_DSN=${MESSENGER_URL}?access_key=${MESSENGER_ACCESS_KEY}"&"secret_key=${MESSENGER_SECRET_KEY}
DATABASE_URL=mysql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}/${DB_NAME}
MAILER_DSN=smtp://${SMTP_USER}:${SMTP_PASSWORD}@${SMTP_HOST}
RESET_PASSWORD_URL=https://${HOST}/cabinet/reset-password/

WORKDIR=/home/ec2-user

cd ${WORKDIR}

echo -e '\033[42m[Run->]\033[0m yum update'
yum update -y

echo -e '\033[42m[Run->]\033[0m Make swap'
dd if=/dev/zero of=/swapfile bs=128M count=16
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

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
docker run --rm -v --interactive --tty --env DATABASE_URL --volume $WORKDIR/api:/app composer:2 install --ignore-platform-reqs --no-dev

echo -e '\033[42m[Run->]\033[0m Building php image'
docker build -f $WORKDIR/docker-api/php/Dockerfile -t php_editor .

echo -e '\033[42m[Run->]\033[0m Building nginx image'
docker build \
  --build-arg HOST=$HOST \
  --build-arg WEBSOCKET_PASS=$WEBSOCKET_PASS \
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
    --env MAIN_SITE_URL=$HOST \
    --env RESET_PASSWORD_URL=$RESET_PASSWORD_URL \
    --env AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    --env AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    --env AWS_S3_BUCKET_NAME=$S3_BUCKET_NAME \
    --env FONDY_SECRET_KEY=$FONDY_SECRET_KEY \
    --name php_editor php_editor

echo -e '\033[42m[Run->]\033[0m Run nginx container'
docker run -d --network=editor -p 80:80 --restart=always --name nginx_editor nginx_editor

echo -e '\033[42m[Run->]\033[0m Migrations'
docker exec php_editor bin/console d:m:m -n

echo -e '\033[42m[Run->]\033[0m Generate JWT sertificates'
docker exec php_editor bin/console lexik:jwt:generate-keypair

echo -e '\033[42m[Run->]\033[0m Setup cron job'
crontab -u ec2-user -l > mycron
echo "0 2 * * * docker exec php_editor php bin/console app:check-subscriptions" >> mycron
crontab -u ec2-user mycron
rm mycron
