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

echo -e "${BLUE}=== Setup GCP Network Infrastructure per AIchemy ===${NC}"

# 1. Crea VPC Network
echo -e "${GREEN}[1/8] Creazione VPC Network...${NC}"
gcloud compute networks create ${NETWORK_NAME} \
  --subnet-mode=custom \
  --bgp-routing-mode=regional \
  --project=${PROJECT_ID}

# 2. Create Public Subnet (per servizi esposti)
echo -e "${GREEN}[2/8] Creazione Subnet Pubblica...${NC}"
gcloud compute networks subnets create ${SUBNET_PUBLIC} \
  --network=${NETWORK_NAME} \
  --region=${REGION} \
  --range=10.0.0.0/24 \
  --enable-private-ip-google-access \
  --enable-flow-logs \
  --project=${PROJECT_ID}

# 3. Crea Subnet Privata (per workload AIchemy)
echo -e "${GREEN}[3/8] Creazione Subnet Privata con Secondary Ranges per GKE...${NC}"
gcloud compute networks subnets create ${SUBNET_PRIVATE} \
  --network=${NETWORK_NAME} \
  --region=${REGION} \
  --range=10.1.0.0/20 \
  --secondary-range pods=10.2.0.0/16 \
  --secondary-range services=10.3.0.0/20 \
  --enable-private-ip-google-access \
  --enable-flow-logs \
  --project=${PROJECT_ID}

# 4. Crea Cloud Router per NAT
echo -e "${GREEN}[4/8] Creazione Cloud Router...${NC}"
gcloud compute routers create ${NETWORK_NAME}-router \
  --network=${NETWORK_NAME} \
  --region=${REGION} \
  --project=${PROJECT_ID}

# 5. Crea Cloud NAT (per accesso internet da subnet privata)
echo -e "${GREEN}[5/8] Configurazione Cloud NAT...${NC}"
gcloud compute routers nats create ${NETWORK_NAME}-nat \
  --router=${NETWORK_NAME}-router \
  --region=${REGION} \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips \
  --enable-logging \
  --project=${PROJECT_ID}

# 6. Firewall Rules
echo -e "${GREEN}[6/8] Configurazione Firewall Rules...${NC}"

# Allow internal communication
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-internal \
  --network=${NETWORK_NAME} \
  --allow=tcp,udp,icmp \
  --source-ranges=10.0.0.0/8 \
  --description="Allow internal communication within VPC" \
  --project=${PROJECT_ID}

# Allow SSH from IAP (Identity-Aware Proxy)
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-iap-ssh \
  --network=${NETWORK_NAME} \
  --allow=tcp:22 \
  --source-ranges=35.235.240.0/20 \
  --description="Allow SSH via Identity-Aware Proxy" \
  --project=${PROJECT_ID}

# Allow health checks from GCP load balancers
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-health-checks \
  --network=${NETWORK_NAME} \
  --allow=tcp \
  --source-ranges=35.191.0.0/16,130.211.0.0/22 \
  --description="Allow health checks from GCP load balancers" \
  --project=${PROJECT_ID}

# Allow Trino coordinator-worker communication
gcloud compute firewall-rules create ${NETWORK_NAME}-allow-trino \
  --network=${NETWORK_NAME} \
  --allow=tcp:8080,tcp:9083 \
  --source-ranges=10.0.0.0/8 \
  --target-tags=gke-node \
  --description="Allow Trino and Hive Metastore communication" \
  --project=${PROJECT_ID}

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