#!/bin/bash

# Configuration
export AWS_REGION="eu-west-1"
export PROJECT_NAME="aichemy"
export ENV="test"
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_CIDR="10.0.0.0/24"
export PRIVATE_SUBNET_1_CIDR="10.1.0.0/20"
export PRIVATE_SUBNET_2_CIDR="10.1.16.0/20"
export CLUSTER_NAME="${PROJECT_NAME}-${ENV}-cluster"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setup AWS Network Infrastructure for AIchemy ===${NC}"

# 1. Create VPC
echo -e "${GREEN}[1/12] Creating VPC...${NC}"
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block ${VPC_CIDR} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc-${ENV}},{Key=Project,Value=${PROJECT_NAME}},{Key=Environment,Value=${ENV}}]" \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: ${VPC_ID}"

# Enable DNS hostnames and DNS support
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support

# 2. Create Internet Gateway
echo -e "${GREEN}[2/12] Creating Internet Gateway...${NC}"
IGW_ID=$(aws ec2 create-internet-gateway \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway --vpc-id ${VPC_ID} --internet-gateway-id ${IGW_ID}
echo "Internet Gateway ID: ${IGW_ID}"

# 3. Create Public Subnet
echo -e "${GREEN}[3/12] Creating Public Subnet...${NC}"
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PUBLIC_SUBNET_CIDR} \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-subnet-${ENV}},{Key=Project,Value=${PROJECT_NAME}},{Key=Type,Value=public}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Public Subnet ID: ${PUBLIC_SUBNET_ID}"

# 4. Create Private Subnets (2 AZs for EKS requirement)
echo -e "${GREEN}[4/12] Creating Private Subnets...${NC}"
PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PRIVATE_SUBNET_1_CIDR} \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-subnet-1-${ENV}},{Key=Project,Value=${PROJECT_NAME}},{Key=Type,Value=private},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared}]" \
  --query 'Subnet.SubnetId' \
  --output text)

PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${PRIVATE_SUBNET_2_CIDR} \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-subnet-2-${ENV}},{Key=Project,Value=${PROJECT_NAME}},{Key=Type,Value=private},{Key=kubernetes.io/role/internal-elb,Value=1},{Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Private Subnet 1 ID: ${PRIVATE_SUBNET_1_ID}"
echo "Private Subnet 2 ID: ${PRIVATE_SUBNET_2_ID}"

# 5. Create Elastic IP for NAT Gateway
echo -e "${GREEN}[5/12] Creating Elastic IP for NAT Gateway...${NC}"
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${PROJECT_NAME}-nat-eip-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'AllocationId' \
  --output text)

echo "Elastic IP Allocation ID: ${EIP_ALLOC_ID}"

# 6. Create NAT Gateway in Public Subnet
echo -e "${GREEN}[6/12] Creating NAT Gateway...${NC}"
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id ${PUBLIC_SUBNET_ID} \
  --allocation-id ${EIP_ALLOC_ID} \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-nat-gw-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'NatGateway.NatGatewayId' \
  --output text)

echo "NAT Gateway ID: ${NAT_GW_ID}"
echo -e "${YELLOW}Waiting for NAT Gateway to become available...${NC}"
aws ec2 wait nat-gateway-available --nat-gateway-ids ${NAT_GW_ID}

# 7. Create Route Tables
echo -e "${GREEN}[7/12] Creating Route Tables...${NC}"

# Public Route Table
PUBLIC_RT_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Private Route Table
PRIVATE_RT_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-private-rt-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

echo "Public Route Table ID: ${PUBLIC_RT_ID}"
echo "Private Route Table ID: ${PRIVATE_RT_ID}"

# 8. Create Routes
echo -e "${GREEN}[8/12] Creating Routes...${NC}"

# Route to Internet Gateway for public subnet
aws ec2 create-route \
  --route-table-id ${PUBLIC_RT_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${IGW_ID}

# Route to NAT Gateway for private subnets
aws ec2 create-route \
  --route-table-id ${PRIVATE_RT_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id ${NAT_GW_ID}

# 9. Associate Route Tables with Subnets
echo -e "${GREEN}[9/12] Associating Route Tables...${NC}"
aws ec2 associate-route-table --subnet-id ${PUBLIC_SUBNET_ID} --route-table-id ${PUBLIC_RT_ID}
aws ec2 associate-route-table --subnet-id ${PRIVATE_SUBNET_1_ID} --route-table-id ${PRIVATE_RT_ID}
aws ec2 associate-route-table --subnet-id ${PRIVATE_SUBNET_2_ID} --route-table-id ${PRIVATE_RT_ID}

# 10. Create Security Groups
echo -e "${GREEN}[10/12] Creating Security Groups...${NC}"

# Bastion Security Group
BASTION_SG_ID=$(aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-bastion-sg-${ENV} \
  --description "Security group for bastion host" \
  --vpc-id ${VPC_ID} \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-bastion-sg-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'GroupId' \
  --output text)

# Allow SSH from anywhere (you should restrict this to your IP)
aws ec2 authorize-security-group-ingress \
  --group-id ${BASTION_SG_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# EKS Cluster Security Group
CLUSTER_SG_ID=$(aws ec2 create-security-group \
  --group-name ${PROJECT_NAME}-cluster-sg-${ENV} \
  --description "Security group for EKS cluster" \
  --vpc-id ${VPC_ID} \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT_NAME}-cluster-sg-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --query 'GroupId' \
  --output text)

# Allow all traffic within VPC
aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG_ID} \
  --protocol all \
  --source-group ${CLUSTER_SG_ID}

# Allow traffic from bastion
aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG_ID} \
  --protocol tcp \
  --port 443 \
  --source-group ${BASTION_SG_ID}

# Trino specific ports
aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG_ID} \
  --protocol tcp \
  --port 8080 \
  --cidr ${VPC_CIDR}

aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG_ID} \
  --protocol tcp \
  --port 9083 \
  --cidr ${VPC_CIDR}

echo "Bastion Security Group ID: ${BASTION_SG_ID}"
echo "Cluster Security Group ID: ${CLUSTER_SG_ID}"

# 11. Create IAM Roles for EKS
echo -e "${GREEN}[11/12] Creating IAM Roles for EKS...${NC}"

# EKS Cluster Role
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
  --role-name ${PROJECT_NAME}-eks-cluster-role-${ENV} \
  --assume-role-policy-document file:///tmp/eks-cluster-trust-policy.json \
  --tags Key=Project,Value=${PROJECT_NAME} Key=Environment,Value=${ENV} 2>/dev/null || true

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-eks-cluster-role-${ENV} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# EKS Node Group Role
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
  --role-name ${PROJECT_NAME}-eks-node-role-${ENV} \
  --assume-role-policy-document file:///tmp/eks-node-trust-policy.json \
  --tags Key=Project,Value=${PROJECT_NAME} Key=Environment,Value=${ENV} 2>/dev/null || true

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-eks-node-role-${ENV} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-eks-node-role-${ENV} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-eks-node-role-${ENV} \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name ${PROJECT_NAME}-eks-node-role-${ENV} \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Get role ARNs
CLUSTER_ROLE_ARN=$(aws iam get-role --role-name ${PROJECT_NAME}-eks-cluster-role-${ENV} --query 'Role.Arn' --output text)
NODE_ROLE_ARN=$(aws iam get-role --role-name ${PROJECT_NAME}-eks-node-role-${ENV} --query 'Role.Arn' --output text)

echo "Cluster Role ARN: ${CLUSTER_ROLE_ARN}"
echo "Node Role ARN: ${NODE_ROLE_ARN}"

# Wait for IAM roles to propagate
echo -e "${YELLOW}Waiting for IAM roles to propagate...${NC}"
sleep 10

# 12. Create EKS Cluster
echo -e "${GREEN}[12/12] Creating EKS Cluster...${NC}"
echo -e "${YELLOW}This will take 10-15 minutes...${NC}"

aws eks create-cluster \
  --region ${AWS_REGION} \
  --name ${CLUSTER_NAME} \
  --kubernetes-version 1.31 \
  --role-arn ${CLUSTER_ROLE_ARN} \
  --resources-vpc-config subnetIds=${PRIVATE_SUBNET_1_ID},${PRIVATE_SUBNET_2_ID},securityGroupIds=${CLUSTER_SG_ID},endpointPublicAccess=false,endpointPrivateAccess=true \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
  --tags Project=${PROJECT_NAME},Environment=${ENV}

echo -e "${YELLOW}Waiting for EKS cluster to become active...${NC}"
aws eks wait cluster-active --name ${CLUSTER_NAME} --region ${AWS_REGION}

# Create Node Group
echo -e "${GREEN}Creating EKS Node Group...${NC}"
aws eks create-nodegroup \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${PROJECT_NAME}-node-group-${ENV} \
  --scaling-config minSize=2,maxSize=6,desiredSize=2 \
  --disk-size 100 \
  --subnets ${PRIVATE_SUBNET_1_ID} ${PRIVATE_SUBNET_2_ID} \
  --instance-types m5.2xlarge \
  --node-role ${NODE_ROLE_ARN} \
  --labels workload=aichemy \
  --tags Project=${PROJECT_NAME},Environment=${ENV} \
  --region ${AWS_REGION}

echo -e "${YELLOW}Waiting for node group to become active...${NC}"
aws eks wait nodegroup-active \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${PROJECT_NAME}-node-group-${ENV} \
  --region ${AWS_REGION}

# Create Bastion Host
echo -e "${GREEN}Creating Bastion Host...${NC}"

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

BASTION_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t3.micro \
  --subnet-id ${PUBLIC_SUBNET_ID} \
  --security-group-ids ${BASTION_SG_ID} \
  --associate-public-ip-address \
  --iam-instance-profile Name=SSMInstanceProfile \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-bastion-${ENV}},{Key=Project,Value=${PROJECT_NAME}}]" \
  --user-data '#!/bin/bash
yum update -y
yum install -y kubectl
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install' \
  --query 'Instances[0].InstanceId' \
  --output text) 2>/dev/null || echo "Bastion creation skipped (SSM profile may not exist)"

echo -e "${BLUE}=== Setup Completed! ===${NC}"
echo ""
echo "Infrastructure Information:"
echo "  VPC ID: ${VPC_ID}"
echo "  VPC CIDR: ${VPC_CIDR}"
echo "  Public Subnet: ${PUBLIC_SUBNET_ID} (${PUBLIC_SUBNET_CIDR})"
echo "  Private Subnet 1: ${PRIVATE_SUBNET_1_ID} (${PRIVATE_SUBNET_1_CIDR})"
echo "  Private Subnet 2: ${PRIVATE_SUBNET_2_ID} (${PRIVATE_SUBNET_2_CIDR})"
echo "  NAT Gateway: ${NAT_GW_ID}"
echo "  EKS Cluster: ${CLUSTER_NAME}"
echo "  Bastion Security Group: ${BASTION_SG_ID}"
echo "  Cluster Security Group: ${CLUSTER_SG_ID}"
echo ""
echo "To connect to the cluster from bastion:"
echo "  1. aws ssm start-session --target ${BASTION_INSTANCE_ID} --region ${AWS_REGION}"
echo "  2. aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
echo "  3. kubectl get nodes"
echo ""
echo "To connect directly (requires AWS VPN or Direct Connect):"
echo "  aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}"
echo ""
echo "IMPORTANT: Save these IDs for future reference!"