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


# 7. Crea GKE Private Cluster
echo -e "${GREEN}[7/8] Creazione GKE Private Cluster...${NC}"
gcloud container clusters create ${CLUSTER_NAME} \
  --region=${REGION} \
  --node-locations=europe-west1-b,europe-west1-c \
  --network=${NETWORK_NAME} \
  --subnetwork=${SUBNET_PRIVATE} \
  --cluster-secondary-range-name=pods \
  --services-secondary-range-name=services \
  --enable-private-nodes \
  --enable-private-endpoint \
  --master-ipv4-cidr=172.16.0.0/28 \
  --enable-ip-alias \
  --enable-master-authorized-networks \
  --master-authorized-networks=10.0.0.0/24 \
  --machine-type=n2-standard-8 \
  --num-nodes=2 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=6 \
  --node-labels=workload=aichemy \
  --enable-autorepair \
  --enable-autoupgrade \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --disk-size=100 \
  --disk-type=pd-ssd \
  --enable-network-policy \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
  --release-channel=regular \
  --project=${PROJECT_ID}

