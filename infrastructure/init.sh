#!/usr/bin/env bash

echo ""
echo "Prerequisites for deployment: "
echo "1. IAM user with administrator rights"
echo "2. AWS cli configured locally for this user"
echo "3. SSL certificate and private key in PEM format stored locally for https setup"
echo "4. PWGen installed locally for database password generation"
echo ""

# pull application name from package.json
# APPLICATION_NAME=$(cat ../package.json \
#   | grep name \
#   | head -1 \
#   | awk -F: '{ print $2 }' \
#   | sed 's/[",]//g' \
#   | tr -d '[[:space:]]')

APPLICATION_NAME="api"
PWGEN=$(which pwgen)
REPO_URL=$(git config --get remote.origin.url)
REPO_NAME=$(basename -s .git $REPO_URL)
AWS_REGION=$(aws configure get region)
BRANCH="develop"
IMAGE_REPO="ecr-${APPLICATION_NAME}"
DB_NAME="mydb"
DB_USER="admin"
EC2_SSH="ssh_key"
SSL_CERT="api_ssl"
KEY_PATH="~/Downloads/sslforfree/private.pem"
CERT_PATH="~/Downloads/sslforfree/certificate.pem"
SLACK="https://hooks.slack.com/services/xxxxxx"
SLACK_BUCKET="slack-$(pwgen -1 -A 5)"

while true; do
  read -p "Do you have everything up and ready for deployment? " yn
    case $yn in
      [Yy]* ) if [[ -z ${AWS_REGION} || -z ${PWGEN} ]]; then
                false
                echo "Something's not configured. Exiting"
                exit
              fi
                break

                ;;

      [Nn]* ) exit

                ;;

      * ) echo "Please answer yes or no."
            
                ;;
    esac
done

echo ""
echo "Infrastructure bootstrapping"
echo ""


DB_PASS=`pwgen -s -1 14`
read -p "Enter AWS region to deploy to (default ${AWS_REGION}): " AWS_REGION_READ
AWS_REGION=${AWS_REGION_READ:-$AWS_REGION}
read -p "Enter CodeCommit repository branch (default ${BRANCH}): " BRANCH_READ
BRANCH=${BRANCH_READ:-$BRANCH}
read -p "Enter database name (default ${DB_NAME}): " DB_NAME_READ
DB_NAME=${DB_NAME_READ:-$DB_NAME}
read -p "Enter DB user (default ${DB_USER}): " DB_USER_READ
DB_USER=${DB_USER_READ:-$DB_USER}
read -p "Enter EC2 SSH key name (default ${EC2_SSH}): " EC2_SSH_READ
EC2_SSH=${EC2_SSH_READ:-$EC2_SSH}
read -p "Enter absolute path to SSL certificate PEM file (default ${CERT_PATH}): " CERT_PATH_READ
CERT_PATH=${CERT_PATH_READ:-$CERT_PATH}
read -p "Enter absolute path to SSL private PEM file (default ${KEY_PATH}): " KEY_PATH_READ
KEY_PATH=${KEY_PATH_READ:-$KEY_PATH}
read -p "Enter name for SSL certificate (default ${SSL_CERT}): " SSL_CERT_READ
SSL_CERT=${SSL_CERT_READ:-$SSL_CERT}
read -p "Enter Slack webhook URL for CodeBuild notifications (default ${SLACK}): " SLACK_READ
SLACK=${SLACK_READ:-$SLACK}
SSL_ARN="arn:aws:iam::`aws sts get-caller-identity --output text --query 'Account'`:server-certificate/${SSL_CERT}"

echo ""
echo -ne '#####                     (33%)\r'
sleep 1
echo -ne '#############             (66%)\r'
sleep 1
echo -ne '#######################   (100%)\r'
echo -ne '\n'
echo ""


aws iam upload-server-certificate --server-certificate-name ${SSL_CERT} --certificate-body file://${CERT_PATH} --private-key file://${KEY_PATH}
aws ec2 create-key-pair --key-name ${EC2_SSH} --query 'KeyMaterial' --output text > ~/.ssh/${EC2_SSH}.pem && chmod 400 ~/.ssh/${EC2_SSH}.pem
zip /tmp/slack.js.zip slack.js
aws s3api create-bucket --bucket ${SLACK_BUCKET} --acl public-read
aws s3 mv /tmp/slack.js.zip s3://${SLACK_BUCKET}/slack.js.zip 

echo ""
echo "AWS Region: ${AWS_REGION}"
echo "ApplicationName: ${APPLICATION_NAME}"
echo "CodeCommitRepoName: ${REPO_NAME}"
echo "Slack Webhook bucket name: ${SLACK_BUCKET}"
echo ""

aws --region ${AWS_REGION} cloudformation create-stack \
  --stack-name ${APPLICATION_NAME} \
  --template-body file://pipeline.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters \
    "ParameterKey=ApplicationName,ParameterValue=${APPLICATION_NAME}" \
    "ParameterKey=CodeCommitRepoName,ParameterValue=${REPO_NAME}" \
    "ParameterKey=CodeCommitBranch,ParameterValue=${BRANCH}" \
    "ParameterKey=ImageRepo,ParameterValue=${IMAGE_REPO}" \
    "ParameterKey=Database,ParameterValue=${DB_NAME}" \
    "ParameterKey=User,ParameterValue=${DB_USER}" \
    "ParameterKey=Password,ParameterValue=${DB_PASS}" \
    "ParameterKey=CertificateArn,ParameterValue=${SSL_ARN}" \
    "ParameterKey=SshKey,ParameterValue=${EC2_SSH}" \
    "ParameterKey=Slack,ParameterValue=${SLACK}" \
    "ParameterKey=SlackBucket,ParameterValue=${SLACK_BUCKET}" \

    