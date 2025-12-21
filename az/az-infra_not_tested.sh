#!/bin/bash

# Configuration
export SUBSCRIPTION_ID="your-subscription-id"
export RESOURCE_GROUP="aichemy-rg-test-01"
export LOCATION="westeurope"
export VNET_NAME="aichemy-vnet-test-01"
export SUBNET_PUBLIC="aichemy-public-subnet-test-01"
export SUBNET_PRIVATE="aichemy-private-subnet-test-01"
export CLUSTER_NAME="aichemy-test-cluster"
export NAT_GATEWAY_NAME="aichemy-nat-gateway"
export PUBLIC_IP_NAT="aichemy-nat-pip"

# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setup Azure Network Infrastructure per AIchemy ===${NC}"

# Set subscription
az account set --subscription ${SUBSCRIPTION_ID}

# 1. Crea Resource Group
echo -e "${GREEN}[1/9] Creazione Resource Group...${NC}"
az group create \
  --name ${RESOURCE_GROUP} \
  --location ${LOCATION}

# 2. Crea Virtual Network
echo -e "${GREEN}[2/9] Creazione Virtual Network...${NC}"
az network vnet create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${VNET_NAME} \
  --location ${LOCATION} \
  --address-prefixes 10.0.0.0/8

# 3. Crea Subnet Pubblica (per servizi esposti e bastion)
echo -e "${GREEN}[3/9] Creazione Subnet Pubblica...${NC}"
az network vnet subnet create \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PUBLIC} \
  --address-prefixes 10.0.0.0/24

# 4. Crea Subnet Privata (per AKS)
echo -e "${GREEN}[4/9] Creazione Subnet Privata per AKS...${NC}"
az network vnet subnet create \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --address-prefixes 10.1.0.0/20

# 5. Crea Public IP per NAT Gateway
echo -e "${GREEN}[5/9] Creazione Public IP per NAT Gateway...${NC}"
az network public-ip create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${PUBLIC_IP_NAT} \
  --location ${LOCATION} \
  --sku Standard \
  --allocation-method Static

# 6. Crea NAT Gateway (per accesso internet da subnet privata)
echo -e "${GREEN}[6/9] Creazione NAT Gateway...${NC}"
az network nat gateway create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${NAT_GATEWAY_NAME} \
  --location ${LOCATION} \
  --public-ip-addresses ${PUBLIC_IP_NAT} \
  --idle-timeout 10

# Associa NAT Gateway alla subnet privata
az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --nat-gateway ${NAT_GATEWAY_NAME}

# 7. Network Security Groups
echo -e "${GREEN}[7/9] Configurazione Network Security Groups...${NC}"

# NSG per subnet pubblica
az network nsg create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${SUBNET_PUBLIC}-nsg \
  --location ${LOCATION}

# NSG per subnet privata (AKS)
az network nsg create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${SUBNET_PRIVATE}-nsg \
  --location ${LOCATION}

# Allow internal communication nella subnet privata
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${SUBNET_PRIVATE}-nsg \
  --name AllowVnetInbound \
  --priority 100 \
  --source-address-prefixes VirtualNetwork \
  --destination-address-prefixes VirtualNetwork \
  --access Allow \
  --protocol '*' \
  --direction Inbound

# Allow Trino coordinator-worker communication
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${SUBNET_PRIVATE}-nsg \
  --name AllowTrino \
  --priority 110 \
  --source-address-prefixes 10.0.0.0/8 \
  --destination-port-ranges 8080 9083 8443 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound

# Allow Azure Load Balancer health probes
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${SUBNET_PRIVATE}-nsg \
  --name AllowAzureLoadBalancer \
  --priority 120 \
  --source-address-prefixes AzureLoadBalancer \
  --access Allow \
  --protocol '*' \
  --direction Inbound

# Associa NSG alle subnet
az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PUBLIC} \
  --network-security-group ${SUBNET_PUBLIC}-nsg

az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --network-security-group ${SUBNET_PRIVATE}-nsg

# 8. Crea AKS Private Cluster
echo -e "${GREEN}[8/9] Creazione AKS Private Cluster...${NC}"

# Get subnet ID
SUBNET_ID=$(az network vnet subnet show \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --query id -o tsv)

az aks create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${CLUSTER_NAME} \
  --location ${LOCATION} \
  --node-count 2 \
  --node-vm-size Standard_D8s_v3 \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 6 \
  --network-plugin azure \
  --vnet-subnet-id ${SUBNET_ID} \
  --docker-bridge-address 172.17.0.1/16 \
  --dns-service-ip 10.3.0.10 \
  --service-cidr 10.3.0.0/20 \
  --enable-private-cluster \
  --enable-managed-identity \
  --enable-aad \
  --enable-azure-rbac \
  --enable-addons monitoring \
  --enable-defender \
  --node-osdisk-size 100 \
  --node-osdisk-type Managed \
  --nodepool-labels workload=aichemy \
  --zones 1 2 3 \
  --kubernetes-version 1.28 \
  --tier standard \
  --network-policy azure \
  --auto-upgrade-channel stable \
  --node-resource-group ${RESOURCE_GROUP}-aks-nodes

# 9. Crea Bastion Host VM nella subnet pubblica
echo -e "${GREEN}[9/9] Creazione Bastion Host VM...${NC}"

# Crea Public IP per Bastion
az network public-ip create \
  --resource-group ${RESOURCE_GROUP} \
  --name aichemy-bastion-pip \
  --location ${LOCATION} \
  --sku Standard \
  --allocation-method Static

# Crea NIC per Bastion
az network nic create \
  --resource-group ${RESOURCE_GROUP} \
  --name aichemy-bastion-nic \
  --location ${LOCATION} \
  --vnet-name ${VNET_NAME} \
  --subnet ${SUBNET_PUBLIC} \
  --public-ip-address aichemy-bastion-pip

# Allow SSH from Internet to bastion (limitato - considera di usare Azure Bastion invece)
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${SUBNET_PUBLIC}-nsg \
  --name AllowSSH \
  --priority 100 \
  --source-address-prefixes 'Internet' \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound

# Crea Bastion VM
az vm create \
  --resource-group ${RESOURCE_GROUP} \
  --name aichemy-bastion \
  --location ${LOCATION} \
  --nics aichemy-bastion-nic \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --os-disk-size-gb 30 \
  --storage-sku StandardSSD_LRS

# Install Azure CLI e kubectl sul bastion
az vm run-command invoke \
  --resource-group ${RESOURCE_GROUP} \
  --name aichemy-bastion \
  --command-id RunShellScript \
  --scripts "
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    curl -LO 'https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl'
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  "

echo -e "${BLUE}=== Setup Completato! ===${NC}"
echo ""
echo "Informazioni cluster:"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Virtual Network: ${VNET_NAME} (10.0.0.0/8)"
echo "  Subnet Pubblica: ${SUBNET_PUBLIC} (10.0.0.0/24)"
echo "  Subnet Privata: ${SUBNET_PRIVATE} (10.1.0.0/20)"
echo "  Service CIDR: 10.3.0.0/20"
echo "  DNS Service IP: 10.3.0.10"
echo "  Docker Bridge: 172.17.0.1/16"
echo ""
echo "Per connetterti al cluster da bastion:"
echo "  1. ssh azureuser@\$(az network public-ip show -g ${RESOURCE_GROUP} -n aichemy-bastion-pip --query ipAddress -o tsv)"
echo "  2. az login"
echo "  3. az aks get-credentials --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}"
echo "  4. kubectl get nodes"
echo ""
echo "NOTA: Per maggiore sicurezza, considera di usare Azure Bastion invece di una VM con SSH pubblico"
echo "      oppure limita l'accesso SSH solo al tuo IP con --source-address-prefixes nella regola NSG"
