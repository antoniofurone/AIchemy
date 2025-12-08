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
export BASTION_NAME="aichemy-bastion"
export BASTION_NSG="aichemy-bastion-nsg"
export AKS_NSG="aichemy-aks-nsg"

# Colori per output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setup Azure Network Infrastructure per AIchemy ===${NC}"

# Imposta la subscription
az account set --subscription ${SUBSCRIPTION_ID}

# 1. Crea Resource Group
echo -e "${GREEN}[1/10] Creazione Resource Group...${NC}"
az group create \
  --name ${RESOURCE_GROUP} \
  --location ${LOCATION}

# 2. Crea Virtual Network
echo -e "${GREEN}[2/10] Creazione Virtual Network...${NC}"
az network vnet create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${VNET_NAME} \
  --address-prefixes 10.0.0.0/8 \
  --location ${LOCATION}

# 3. Crea Subnet Pubblica (per bastion e servizi esposti)
echo -e "${GREEN}[3/10] Creazione Subnet Pubblica...${NC}"
az network vnet subnet create \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PUBLIC} \
  --address-prefixes 10.0.0.0/24

# 4. Crea Subnet Privata (per AKS)
echo -e "${GREEN}[4/10] Creazione Subnet Privata per AKS...${NC}"
az network vnet subnet create \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --address-prefixes 10.1.0.0/20

# 5. Crea Public IP per NAT Gateway
echo -e "${GREEN}[5/10] Creazione Public IP per NAT Gateway...${NC}"
az network public-ip create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${PUBLIC_IP_NAT} \
  --sku Standard \
  --allocation-method Static \
  --location ${LOCATION}

# 6. Crea NAT Gateway
echo -e "${GREEN}[6/10] Creazione NAT Gateway...${NC}"
az network nat gateway create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${NAT_GATEWAY_NAME} \
  --location ${LOCATION} \
  --public-ip-addresses ${PUBLIC_IP_NAT} \
  --idle-timeout 10

# 7. Associa NAT Gateway alla subnet privata
echo -e "${GREEN}[7/10] Associazione NAT Gateway alla subnet privata...${NC}"
az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --nat-gateway ${NAT_GATEWAY_NAME}

# 8. Crea Network Security Group per AKS
echo -e "${GREEN}[8/10] Configurazione Network Security Groups...${NC}"
az network nsg create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${AKS_NSG} \
  --location ${LOCATION}

# Allow internal communication
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${AKS_NSG} \
  --name AllowInternalCommunication \
  --priority 100 \
  --source-address-prefixes 10.0.0.0/8 \
  --destination-address-prefixes 10.0.0.0/8 \
  --destination-port-ranges '*' \
  --protocol '*' \
  --access Allow \
  --direction Inbound

# Allow Trino coordinator-worker communication
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${AKS_NSG} \
  --name AllowTrino \
  --priority 110 \
  --source-address-prefixes 10.0.0.0/8 \
  --destination-port-ranges 8080 9083 \
  --protocol Tcp \
  --access Allow \
  --direction Inbound

# Allow Azure Load Balancer
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${AKS_NSG} \
  --name AllowAzureLoadBalancer \
  --priority 120 \
  --source-address-prefixes AzureLoadBalancer \
  --destination-port-ranges '*' \
  --protocol '*' \
  --access Allow \
  --direction Inbound

# Associa NSG alla subnet privata
az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --network-security-group ${AKS_NSG}

# NSG per Bastion
az network nsg create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${BASTION_NSG} \
  --location ${LOCATION}

# Allow SSH from anywhere (da restringere in produzione)
az network nsg rule create \
  --resource-group ${RESOURCE_GROUP} \
  --nsg-name ${BASTION_NSG} \
  --name AllowSSH \
  --priority 100 \
  --source-address-prefixes '*' \
  --destination-port-ranges 22 \
  --protocol Tcp \
  --access Allow \
  --direction Inbound

# Associa NSG alla subnet pubblica
az network vnet subnet update \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PUBLIC} \
  --network-security-group ${BASTION_NSG}

# 9. Crea AKS Private Cluster
echo -e "${GREEN}[9/10] Creazione AKS Private Cluster...${NC}"

# Ottieni subnet ID
SUBNET_ID=$(az network vnet subnet show \
  --resource-group ${RESOURCE_GROUP} \
  --vnet-name ${VNET_NAME} \
  --name ${SUBNET_PRIVATE} \
  --query id -o tsv)

az aks create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${CLUSTER_NAME} \
  --location ${LOCATION} \
  --network-plugin azure \
  --vnet-subnet-id ${SUBNET_ID} \
  --service-cidr 10.3.0.0/20 \
  --dns-service-ip 10.3.0.10 \
  --enable-private-cluster \
  --private-dns-zone system \
  --enable-managed-identity \
  --node-vm-size Standard_D8s_v3 \
  --node-count 2 \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 6 \
  --node-osdisk-size 100 \
  --node-osdisk-type Managed \
  --zones 1 2 3 \
  --enable-addons monitoring \
  --enable-aad \
  --enable-azure-rbac \
  --network-policy azure \
  --nodepool-labels workload=aichemy \
  --generate-ssh-keys \
  --tier standard

# 10. Crea Bastion Host
echo -e "${GREEN}[10/10] Creazione Bastion Host...${NC}"

# Public IP per bastion
az network public-ip create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${BASTION_NAME}-pip \
  --sku Standard \
  --allocation-method Static \
  --location ${LOCATION}

# NIC per bastion
az network nic create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${BASTION_NAME}-nic \
  --vnet-name ${VNET_NAME} \
  --subnet ${SUBNET_PUBLIC} \
  --public-ip-address ${BASTION_NAME}-pip \
  --location ${LOCATION}

# VM Bastion
az vm create \
  --resource-group ${RESOURCE_GROUP} \
  --name ${BASTION_NAME} \
  --location ${LOCATION} \
  --nics ${BASTION_NAME}-nic \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --boot-diagnostics-storage ""

# Installa Azure CLI e kubectl sul bastion
az vm run-command invoke \
  --resource-group ${RESOURCE_GROUP} \
  --name ${BASTION_NAME} \
  --command-id RunShellScript \
  --scripts "
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    sudo az aks install-cli
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
echo ""
echo "Per connetterti al cluster da bastion:"
echo "  1. ssh azureuser@\$(az network public-ip show -g ${RESOURCE_GROUP} -n ${BASTION_NAME}-pip --query ipAddress -o tsv)"
echo "  2. az login"
echo "  3. az aks get-credentials --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}"
echo "  4. kubectl get nodes"
echo ""
echo "Per connetterti direttamente (richiede connettività alla VNet):"
echo "  az aks get-credentials --resource-group ${RESOURCE_GROUP} --name ${CLUSTER_NAME}"
echo ""
echo "NOTA: Aggiorna SUBSCRIPTION_ID all'inizio dello script con il tuo Subscription ID"