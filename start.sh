#!/bin/bash

curl https://raw.githubusercontent.com/DeusEditor/aws-api-deploy/main/deploy.sh -o /home/ec2-user/deploy.sh
chmod 764 /home/ec2-user/deploy.sh
/home/ec2-user/deploy.sh
