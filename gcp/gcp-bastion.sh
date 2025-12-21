#!/bin/bash

# Configuration
export PROJECT_ID="aichemy-dev-01"
export REGION="europe-west1"
export NETWORK_NAME="aichemy-vpc-test-01"
export SUBNET_PUBLIC="aichemy-public-subnet-test-01"
export SUBNET_PRIVATE="aichemy-private-subnet-test-01"
export CLUSTER_NAME="aichemy-test-cluster"

# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 8. Crea Bastion Host nella subnet pubblica (per accesso al cluster)
echo -e "${GREEN}[8/8] Creazione Bastion Host...${NC}"
gcloud compute instances create aichemy-bastion \
  --zone=europe-west1-b \
  --machine-type=e2-micro \
  --network-interface=subnet=${SUBNET_PUBLIC},no-address \
  --metadata=enable-oslogin=true \
  --maintenance-policy=MIGRATE \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --tags=bastion \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --boot-disk-type=pd-standard \
  --project=${PROJECT_ID}

# Firewall rule per bastion
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-bastion-to-gke \
  --network=${NETWORK_NAME} \
  --allow=tcp:443 \
  --source-tags=bastion \
  --target-tags=gke-node \
  --description="Allow bastion to access GKE API" \
  --project=${PROJECT_ID}

echo -e "${BLUE}=== Setup Completato! ===${NC}"
echo ""
echo "Informazioni cluster:"
echo "  VPC Network: ${NETWORK_NAME}"
echo "  Subnet Pubblica: ${SUBNET_PUBLIC} (10.0.0.0/24)"
echo "  Subnet Privata: ${SUBNET_PRIVATE} (10.1.0.0/20)"
echo "  Pod Range: 10.2.0.0/16"
echo "  Service Range: 10.3.0.0/20"
echo "  Master Range: 172.16.0.0/28"
echo ""
echo "Per connetterti al cluster da bastion:"
echo "  1. gcloud compute ssh aichemy-bastion --zone=europe-west1-b --tunnel-through-iap"
echo "  2. gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION}"
echo "  3. kubectl get nodes"
echo ""
echo "Per connetterti direttamente (se hai accesso autorizzato):"
echo "  gcloud container clusters get-credentials ${CLUSTER_NAME} --region=${REGION} --internal-ip"