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

# eseguire comanda come da ultimo ste aws-iam.sh
#export EKS_CLUSTER_ROLE_ARN="arn:aws:iam::719768632770:role/aichemy-test-cluster-cluster-role"
# eseguire comanda come da ultimo ste aws-iam-ng.sh
#export EKS_NODE_ROLE_ARN="arn:aws:iam::719768632770:role/aichemy-test-cluster-node-role"

# Recupera dinamicamente gli ID delle risorse esistenti
echo "Recupero risorse esistenti..."

EKS_CLUSTER_ROLE_ARN=$(aws iam get-role \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --query 'Role.Arn' \
  --output text)

EKS_NODE_ROLE_ARN=$(aws iam get-role \
  --role-name ${CLUSTER_NAME}-node-role \
  --query 'Role.Arn' \
  --output text)  

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --region ${AWS_REGION})

PRIVATE_SUBNET_1_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=cidr-block,Values=${PRIVATE_SUBNET_1_CIDR}" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --region ${AWS_REGION})

PRIVATE_SUBNET_2_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=cidr-block,Values=${PRIVATE_SUBNET_2_CIDR}" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --region ${AWS_REGION})

EKS_CONTROL_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${VPC_NAME}-eks-control-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region ${AWS_REGION})

echo "EKS_CLUSTER_ROLE_ARN: ${EKS_CLUSTER_ROLE_ARN}"
echo "EKS_NODE_ROLE_ARN: ${EKS_NODE_ROLE_ARN}"
echo "VPC ID: ${VPC_ID}"
echo "Private Subnet 1 ID: ${PRIVATE_SUBNET_1_ID}"
echo "Private Subnet 2 ID: ${PRIVATE_SUBNET_2_ID}"
echo "EKS Control SG ID: ${EKS_CONTROL_SG_ID}"


# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color




# Crea Node Group
echo -e "${GREEN}Creazione Node Group...${NC}"
aws eks create-nodegroup \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${CLUSTER_NAME}-node-group \
  --scaling-config minSize=2,maxSize=6,desiredSize=2 \
  --disk-size 100 \
  --subnets ${PRIVATE_SUBNET_1_ID} ${PRIVATE_SUBNET_2_ID} \
  --instance-types t3.2xlarge \
  --node-role ${EKS_NODE_ROLE_ARN} \
  --labels workload=aichemy \
  --tags "Name=${CLUSTER_NAME}-node-group,Environment=test" \
  --region ${AWS_REGION}

echo "Attendi che il node group sia attivo..."
aws eks wait nodegroup-active \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${CLUSTER_NAME}-node-group \
  --region ${AWS_REGION}

