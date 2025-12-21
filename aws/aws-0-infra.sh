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

echo -e "${BLUE}=== Setup AWS Network Infrastructure per AIchemy ===${NC}"

# 1. Crea VPC
echo -e "${GREEN}[1/15] Creazione VPC...${NC}"
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block ${VPC_CIDR} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC creata: ${VPC_ID}"

# Enable DNS hostname
aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames \
  --region ${AWS_REGION}

# 2. Crea Internet Gateway
echo -e "${GREEN}[2/15] Creazione Internet Gateway...${NC}"
IGW_ID=$(aws ec2 create-internet-gateway \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --vpc-id ${VPC_ID} \
  --internet-gateway-id ${IGW_ID} \
  --region ${AWS_REGION}

echo "Internet Gateway creato: ${IGW_ID}"

# 3. Crea Subnet Pubblica
echo -e "${GREEN}[3/15] Creazione Subnet Pubblica...${NC}"
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PUBLIC_SUBNET_CIDR} \
  --availability-zone ${AZ1} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public-subnet},{Key=kubernetes.io/role/elb,Value=1}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subnet pubblica creata: ${PUBLIC_SUBNET_ID}"

# 4. Crea Subnet Private per EKS (2 AZ per HA)
echo -e "${GREEN}[4/15] Creazione Subnet Private...${NC}"
PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PRIVATE_SUBNET_1_CIDR} \
  --availability-zone ${AZ1} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-subnet-1},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared}]" \
  --query 'Subnet.SubnetId' \
  --output text)

PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PRIVATE_SUBNET_2_CIDR} \
  --availability-zone ${AZ2} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-subnet-2},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subnet private create: ${PRIVATE_SUBNET_1_ID}, ${PRIVATE_SUBNET_2_ID}"

# 5. Alloca Elastic IP per NAT Gateway
echo -e "${GREEN}[5/15] Allocazione Elastic IP per NAT Gateway...${NC}"
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-nat-eip}]" \
  --query 'AllocationId' \
  --output text)

echo "Elastic IP allocato: ${EIP_ALLOC_ID}"

# 6. Crea NAT Gateway nella subnet pubblica
echo -e "${GREEN}[6/15] Creazione NAT Gateway...${NC}"
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id ${PUBLIC_SUBNET_ID} \
  --allocation-id ${EIP_ALLOC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat}]" \
  --query 'NatGateway.NatGatewayId' \
  --output text)

echo "NAT Gateway creato: ${NAT_GW_ID}"
echo "Attendi che il NAT Gateway diventi disponibile..."
aws ec2 wait nat-gateway-available --nat-gateway-ids ${NAT_GW_ID} --region ${AWS_REGION}

# 7. Crea Route Table Pubblica
echo -e "${GREEN}[7/15] Configurazione Route Table Pubblica...${NC}"
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id ${PUBLIC_RT_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${IGW_ID} \
  --region ${AWS_REGION}

aws ec2 associate-route-table \
  --subnet-id ${PUBLIC_SUBNET_ID} \
  --route-table-id ${PUBLIC_RT_ID} \
  --region ${AWS_REGION}

echo "Route Table pubblica creata: ${PUBLIC_RT_ID}"

# 8. Crea Route Table Privata
echo -e "${GREEN}[8/15] Configurazione Route Table Privata...${NC}"
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --route-table-id ${PRIVATE_RT_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id ${NAT_GW_ID} \
  --region ${AWS_REGION}

aws ec2 associate-route-table \
  --subnet-id ${PRIVATE_SUBNET_1_ID} \
  --route-table-id ${PRIVATE_RT_ID} \
  --region ${AWS_REGION}

aws ec2 associate-route-table \
  --subnet-id ${PRIVATE_SUBNET_2_ID} \
  --route-table-id ${PRIVATE_RT_ID} \
  --region ${AWS_REGION}

echo "Route Table privata creata: ${PRIVATE_RT_ID}"

# 9. Crea Security Group per Bastion
echo -e "${GREEN}[9/15] Creazione Security Group per Bastion...${NC}"
BASTION_SG_ID=$(aws ec2 create-security-group \
  --group-name ${VPC_NAME}-bastion-sg \
  --description "Security group for bastion host" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${VPC_NAME}-bastion-sg}]" \
  --query 'GroupId' \
  --output text)

# Allow SSH only from your IP (modifica con il tuo IP)
aws ec2 authorize-security-group-ingress \
  --group-id ${BASTION_SG_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region ${AWS_REGION}

echo "Bastion SG creato: ${BASTION_SG_ID}"

# 10. Crea Security Group per EKS Control Plane
echo -e "${GREEN}[10/15] Creazione Security Group per EKS Control Plane...${NC}"
EKS_CONTROL_SG_ID=$(aws ec2 create-security-group \
  --group-name ${VPC_NAME}-eks-control-sg \
  --description "Security group for EKS control plane" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${VPC_NAME}-eks-control-sg}]" \
  --query 'GroupId' \
  --output text)

echo "EKS Control Plane SG creato: ${EKS_CONTROL_SG_ID}"

# 11. Crea Security Group per EKS Nodes
echo -e "${GREEN}[11/15] Creazione Security Group per EKS Nodes...${NC}"
EKS_NODE_SG_ID=$(aws ec2 create-security-group \
  --group-name ${VPC_NAME}-eks-node-sg \
  --description "Security group for EKS worker nodes" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${VPC_NAME}-eks-node-sg},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=owned}]" \
  --query 'GroupId' \
  --output text)

# Allow all traffic between nodes
aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol -1 \
  --source-group ${EKS_NODE_SG_ID} \
  --region ${AWS_REGION}

# Allow traffic from control plane
aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 443 \
  --source-group ${EKS_CONTROL_SG_ID} \
  --region ${AWS_REGION}

aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 1025-65535 \
  --source-group ${EKS_CONTROL_SG_ID} \
  --region ${AWS_REGION}

# Allow SSH from bastion
aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 22 \
  --source-group ${BASTION_SG_ID} \
  --region ${AWS_REGION}

# Allow Trino ports
aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 8080 \
  --source-group ${EKS_NODE_SG_ID} \
  --region ${AWS_REGION}

aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 8443 \
  --source-group ${EKS_NODE_SG_ID} \
  --region ${AWS_REGION}

aws ec2 authorize-security-group-ingress \
  --group-id ${EKS_NODE_SG_ID} \
  --protocol tcp \
  --port 9083 \
  --source-group ${EKS_NODE_SG_ID} \
  --region ${AWS_REGION}

echo "EKS Node SG creato: ${EKS_NODE_SG_ID}"

