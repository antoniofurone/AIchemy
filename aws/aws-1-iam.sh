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


# 12. Crea IAM Role per EKS Cluster
echo -e "${GREEN}[12/15] Creazione IAM Role per EKS Cluster...${NC}"

cat > /tmp/eks-cluster-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --assume-role-policy-document file:///tmp/eks-cluster-trust-policy.json \
  --region ${AWS_REGION} 2>/dev/null || echo "Role già esistente"

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  --region ${AWS_REGION}

aws iam attach-role-policy \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController \
  --region ${AWS_REGION}

EKS_CLUSTER_ROLE_ARN=$(aws iam get-role \
  --role-name ${CLUSTER_NAME}-cluster-role \
  --query 'Role.Arn' \
  --output text)

echo "EKS Cluster Role ARN: ${EKS_CLUSTER_ROLE_ARN}"


