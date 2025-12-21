#!/bin/bash

# Configuration
export AWS_REGION="eu-west-1"
export CLUSTER_NAME="aichemy-test-cluster"
export VPC_NAME="aichemy-vpc-test-01"
export KEY_NAME="aichemy-bastion-key"  # Crea prima la keypair: aws ec2 create-key-pair --key-name aichemy-bastion-key

# CIDR Blocks
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_CIDR="10.0.0.0/24"
export PRIVATE_SUBNET_1_CIDR="10.0.1.0/24"
export PRIVATE_SUBNET_2_CIDR="10.0.2.0/24"

# Availability Zones
export AZ1="${AWS_REGION}a"
export AZ2="${AWS_REGION}b"


# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# Recupera dinamicamente gli ID delle risorse esistenti
echo "Recupero risorse esistenti..."

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region ${AWS_REGION})

PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=cidr-block,Values=${PUBLIC_SUBNET_CIDR}" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --region ${AWS_REGION})

BASTION_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${VPC_NAME}-bastion-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region ${AWS_REGION})

echo "VPC ID: ${VPC_ID}"
echo "Public Subnet ID: ${PUBLIC_SUBNET_ID}"
echo "Bastion SG ID: ${BASTION_SG_ID}"


# 15. Crea Bastion Host
echo -e "${GREEN}[15/15] Creazione Bastion Host...${NC}"

# Verifica se la keypair esiste, altrimenti la crea
echo "Verifica keypair..."
aws ec2 describe-key-pairs --key-names ${KEY_NAME} --region ${AWS_REGION} 2>/dev/null
if [ $? -ne 0 ]; then
  echo "Keypair non trovata. Creazione in corso..."
  mkdir -p ~/.ssh
  aws ec2 create-key-pair \
    --key-name ${KEY_NAME} \
    --query 'KeyMaterial' \
    --output text \
    --region ${AWS_REGION} > ~/.ssh/${KEY_NAME}.pem 2>&1
  
  if [ $? -eq 0 ] && [ -f ~/.ssh/${KEY_NAME}.pem ]; then
    chmod 400 ~/.ssh/${KEY_NAME}.pem
    echo "Keypair creata e salvata in ~/.ssh/${KEY_NAME}.pem"
  else
    echo "Errore nella creazione della keypair"
    exit 1
  fi
else
  echo "Keypair ${KEY_NAME} già esistente"
fi

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --region ${AWS_REGION})

BASTION_ID=$(aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.micro \
  --key-name ${KEY_NAME} \
  --subnet-id ${PUBLIC_SUBNET_ID} \
  --security-group-ids ${BASTION_SG_ID} \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=aichemy-bastion}]" \
  --region ${AWS_REGION} \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Bastion Host creato: ${BASTION_ID}"

# Update kubeconfig
echo -e "${GREEN}Aggiornamento kubeconfig locale...${NC}"
aws eks update-kubeconfig \
  --region ${AWS_REGION} \
  --name ${CLUSTER_NAME}

echo -e "${BLUE}=== Setup Completato! ===${NC}"
echo ""
echo "Informazioni cluster:"
echo "  VPC ID: ${VPC_ID}"
echo "  Region: ${AWS_REGION}"
echo "  Subnet Pubblica: ${PUBLIC_SUBNET_ID} (${PUBLIC_SUBNET_CIDR})"
echo "  Subnet Private: ${PRIVATE_SUBNET_1_ID} (${PRIVATE_SUBNET_1_CIDR})"
echo "                  ${PRIVATE_SUBNET_2_ID} (${PRIVATE_SUBNET_2_CIDR})"
echo "  EKS Cluster: ${CLUSTER_NAME}"
echo "  Bastion: ${BASTION_ID}"
echo ""
echo "Per connetterti al cluster:"
echo "  aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}"
echo "  kubectl get nodes"
echo ""
echo "Per SSH al bastion:"
echo "  aws ec2-instance-connect ssh --instance-id ${BASTION_ID} --region ${AWS_REGION}"
echo "  oppure: ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@<BASTION_PUBLIC_IP>"
echo ""
echo "IMPORTANTE: Crea la keypair prima di eseguire lo script:"
echo "  aws ec2 create-key-pair --key-name ${KEY_NAME} --query 'KeyMaterial' --output text > ~/.ssh/${KEY_NAME}.pem"
echo "  chmod 400 ~/.ssh/${KEY_NAME}.pem"
