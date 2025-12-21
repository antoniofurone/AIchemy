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
export EKS_CLUSTER_ROLE_ARN="arn:aws:iam::719768632770:role/aichemy-test-cluster-cluster-role"

# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 14. Crea IAM Role per Node Group
echo -e "${GREEN}[14/15] Creazione IAM Role per Node Group...${NC}"

cat > /tmp/eks-node-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${CLUSTER_NAME}-node-role \
  --assume-role-policy-document file:///tmp/eks-node-trust-policy.json \
  --region ${AWS_REGION} 2>/dev/null || echo "Role già esistente"

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  --region ${AWS_REGION}

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  --region ${AWS_REGION}

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  --region ${AWS_REGION}

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --region ${AWS_REGION}

EKS_NODE_ROLE_ARN=$(aws iam get-role \
  --role-name ${CLUSTER_NAME}-node-role \
  --query 'Role.Arn' \
  --output text)

echo "EKS Node Role ARN: ${EKS_NODE_ROLE_ARN}"

