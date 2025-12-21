# AIchemy GCP Architecture

This directory contains the infrastructure and deployment configurations for running the AIchemy data lakehouse platform on GCP GKE (Google Kubernetes Engine).

## Architecture Overview

The AIchemy platform provides a complete data lakehouse solution with support for multiple table formats (Hive, Iceberg, Delta Lake, Lance) running on Kubernetes with Trino as the query engine and MinIO as S3-compatible storage.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        GCP Cloud - VPC Network                          │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │              GKE Cluster (Private Nodes)                         │   │
│  │            europe-west1-b, europe-west1-c                        │   │
│  │                                                                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │              Trino Namespace                               │  │   │
│  │  │                                                            │  │   │
│  │  │  ┌─────────────────┐         ┌─────────────────┐           │  │   │
│  │  │  │ Trino Coord.    │         │ Trino Worker    │           │  │   │
│  │  │  │ (1 replica)     │◄───────►│ (2 replicas)    │           │  │   │
│  │  │  │                 │         │                 │           │  │   │
│  │  │  │ • HTTP :8080    │         │ • HTTP :8080    │           │  │   │
│  │  │  │ • HTTPS :8443   │         │ • HTTPS :8443   │           │  │   │
│  │  │  │ • Auth: Password│         │ • Shared Secret │           │  │   │
│  │  │  └────────┬────────┘         └────────┬────────┘           │  │   │
│  │  │           │                           │                    │  │   │
│  │  │           └───────────┬───────────────┘                    │  │   │
│  │  │                       │                                    │  │   │
│  │  │                       ▼                                    │  │   │
│  │  │           ┌───────────────────────┐                        │  │   │
│  │  │           │  Hive Metastore       │                        │  │   │
│  │  │           │  (1 replica)          │                        │  │   │
│  │  │           │                       │                        │  │   │
│  │  │           │  • Thrift :9083       │                        │  │   │
│  │  │           │  • S3 Support         │                        │  │   │
│  │  │           └───────────┬───────────┘                        │  │   │
│  │  │                       │                                    │  │   │
│  │  │                       ▼                                    │  │   │
│  │  │           ┌───────────────────────┐                        │  │   │
│  │  │           │  PostgreSQL           │                        │  │   │
│  │  │           │  (StatefulSet)        │                        │  │   │
│  │  │           │                       │                        │  │   │
│  │  │           │  • Port :5432         │                        │  │   │
│  │  │           │  • Storage: PD-SSD    │                        │  │   │
│  │  │           └───────────────────────┘                        │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐  │   │
│  │  │              MinIO Namespace (HA)                          │  │   │
│  │  │                                                            │  │   │
│  │  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                    │  │   │
│  │  │  │MinIO │  │MinIO │  │MinIO │  │MinIO │                    │  │   │
│  │  │  │Pod-0 │  │Pod-1 │  │Pod-2 │  │Pod-3 │                    │  │   │
│  │  │  │      │  │      │  │      │  │      │                    │  │   │
│  │  │  │:9000 │  │:9000 │  │:9000 │  │:9000 │                    │  │   │
│  │  │  │:9001 │  │:9001 │  │:9001 │  │:9001 │                    │  │   │
│  │  │  └───┬──┘  └───┬──┘  └───┬──┘  └───┬──┘                    │  │   │
│  │  │      │         │         │         │                       │  │   │
│  │  │      └─────────┴─────────┴─────────┘                       │  │   │
│  │  │                    │                                       │  │   │
│  │  │            ┌───────▼────────┐                              │  │   │
│  │  │            │ Persistent Disk│                              │  │   │
│  │  │            │ (4x 10Gi SSD)  │                              │  │   │
│  │  │            └────────────────┘                              │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    External Access                               │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐         ┌────────────────────┐           │   │
│  │  │ GCP External LB    │         │ GCP External LB    │           │   │
│  │  │ (Trino External)   │         │ (MinIO Console)    │           │   │
│  │  │                    │         │                    │           │   │
│  │  │ • HTTPS :8443      │         │ • API :9000        │           │   │
│  │  │ • HTTP  :8080      │         │ • Console :9001    │           │   │
│  │  └────────────────────┘         └────────────────────┘           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    Public Subnet                                 │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐                                          │   │
│  │  │ Bastion Host       │                                          │   │
│  │  │ (e2-micro)         │                                          │   │
│  │  │                    │                                          │   │
│  │  │ • SSH via IAP      │                                          │   │
│  │  │ • kubectl access   │                                          │   │
│  │  └────────────────────┘                                          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Trino Query Engine

**Purpose**: Distributed SQL query engine for data lakehouse workloads

**Architecture**:
- **Coordinator** (1 replica): Manages query planning, parsing, and client connections
- **Workers** (2 replicas): Execute query tasks in parallel

**Security**:
- HTTPS enabled on port 8443 with self-signed certificates (auto-generated)
- Password authentication required for external clients
  - `admin` / `admin123`
  - `user1` / `user123`
- Internal communication via HTTP (port 8080) with shared secret

**Catalogs**:
- **Hive**: Traditional data warehouse tables
- **Iceberg**: Modern table format with ACID, time travel, schema evolution
- **Delta Lake**: Databricks-compatible table format
- **Lance**: Vector embeddings and ML-optimized storage

**Resources**:
- Request: 4Gi RAM, 2 CPU per pod
- Limit: 8Gi RAM, 4 CPU per pod

### 2. MinIO Object Storage (HA)

**Purpose**: S3-compatible object storage for data lake files

**Architecture**:
- 4-node distributed deployment with erasure coding
- Tolerates up to 2 node failures
- StatefulSet with persistent storage

**Storage**:
- 4 Persistent Disks (standard-rwo storage class)
- 10Gi per volume (40Gi total)

**Endpoints**:
- API: port 9000
- Console: port 9001

**Credentials**:
- Access Key: `admin`
- Secret Key: `password123`

### 3. Hive Metastore

**Purpose**: Centralized metadata catalog for all table formats

**Features**:
- Stores table schemas, partitions, and locations
- Connects to PostgreSQL for metadata persistence
- S3-compatible storage support via Hadoop AWS libraries

**Dependencies**:
- PostgreSQL JDBC driver (auto-downloaded)
- Hadoop AWS + AWS SDK bundles (auto-downloaded)

### 4. PostgreSQL Database

**Purpose**: Persistent metadata storage for Hive Metastore

**Configuration**:
- Database: `metastore`
- User: `hive`
- Password: `hivepassword`

**Storage**:
- 10Gi Persistent Disk (standard-rwo storage class)
- Deployed as StatefulSet for data persistence

## Data Flow

1. **Client Query** → Trino Coordinator (HTTPS :8443 with password auth)
2. **Query Planning** → Coordinator distributes tasks to Workers
3. **Metadata Lookup** → Workers query Hive Metastore (Thrift :9083)
4. **Metastore Query** → PostgreSQL database (:5432)
5. **Data Read/Write** → MinIO S3 API (:9000)
6. **Results** → Aggregated and returned to client

## Network Communication

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| External Client | Trino Coordinator | 8443 | HTTPS | User queries (password auth) |
| Coordinator | Workers | 8080 | HTTP | Internal communication (shared secret) |
| Trino | Hive Metastore | 9083 | Thrift | Metadata operations |
| Hive Metastore | PostgreSQL | 5432 | TCP | Metadata storage |
| Trino/Metastore | MinIO | 9000 | HTTP | S3 object storage |
| External Client | MinIO Console | 9001 | HTTP | MinIO administration |
| Bastion | GKE API | 443 | HTTPS | Cluster management |

## Infrastructure Setup

The infrastructure is provisioned using shell scripts:

### 1. `gcp-infra.sh` - VPC and Network Setup
- Creates custom VPC network
- Configures public subnet (10.0.0.0/24) for bastion
- Configures private subnet (10.1.0.0/20) for GKE nodes
- Sets up secondary ranges for pods (10.2.0.0/16) and services (10.3.0.0/20)
- Creates Cloud Router and Cloud NAT for internet access
- Configures firewall rules (internal, IAP SSH, health checks, Trino)

### 2. `gcp-gke.sh` - GKE Cluster Creation
- Creates private GKE cluster with regional deployment
- Configures master authorized networks
- Enables Workload Identity
- Sets up autoscaling (2-6 nodes)
- Configures monitoring and logging
- Enables shielded nodes with secure boot

### 3. Bastion Host Setup
- Creates e2-micro instance in public subnet
- Enables OS Login and IAP
- Configures access to GKE API
- Used for cluster management via SSH tunnel

## GKE Cluster Configuration

### Node Configuration
- **Machine Type**: n2-standard-8 (8 vCPU, 32GB RAM)
- **Nodes**: 2 (min) to 6 (max) with autoscaling
- **Disk**: 100GB SSD per node
- **Zones**: europe-west1-b, europe-west1-c

### Network
- **VPC**: Custom VPC (aichemy-vpc-test-01)
- **Subnet**: Private subnet with secondary ranges
- **Master CIDR**: 172.16.0.0/28
- **Pod CIDR**: 10.2.0.0/16
- **Service CIDR**: 10.3.0.0/20

### Security Features
- Private nodes (no external IPs)
- Private endpoint (master accessible only from authorized networks)
- Workload Identity enabled
- Shielded nodes with secure boot
- Network policy enabled

## Storage Classes

### standard-rwo (Regional Persistent Disk)
```yaml
storageClassName: "standard-rwo"
```
- Used for PostgreSQL and MinIO persistent volumes
- GCP Persistent Disk (Regional)
- Synchronously replicated across zones

## Deployment Instructions

### Prerequisites
1. GCP account with billing enabled
2. `gcloud` CLI installed and authenticated
3. Project created with necessary APIs enabled:
   - Compute Engine API
   - Kubernetes Engine API
   - Cloud Resource Manager API

### Step 1: Set Project Variables

```bash
# Set your GCP project
export PROJECT_ID="your-project-id"
export REGION="europe-west1"
export CLUSTER_NAME="aichemy-test-cluster"

# Authenticate
gcloud auth login
gcloud config set project ${PROJECT_ID}
```

### Step 2: Infrastructure Setup

```bash
cd gcp

# Run infrastructure setup
chmod +x gcp-infra.sh
./gcp-infra.sh
```

This script will create:
- VPC network with subnets
- Cloud Router and NAT
- Firewall rules
- GKE private cluster
- Bastion host

**Note**: The script takes approximately 10-15 minutes to complete.

### Step 3: Connect to Cluster

#### Option A: Via Bastion (Recommended for Private Cluster)

```bash
# SSH to bastion with IAP tunnel
gcloud compute ssh aichemy-bastion \
  --zone=europe-west1-b \
  --tunnel-through-iap

# Inside bastion, get cluster credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --region=${REGION} \
  --internal-ip

# Verify connection
kubectl get nodes
```

#### Option B: Direct Access (If Authorized Network Configured)

```bash
# Get credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --region=${REGION}

# Verify
kubectl get nodes
```

### Step 4: Install gke-gcloud-auth-plugin (On Bastion)

```bash
# Install kubectl and auth plugin
sudo apt-get update
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin

# Verify installation
kubectl version --client
gke-gcloud-auth-plugin --version
```

### Step 5: Deploy MinIO

```bash
# Apply MinIO HA configuration
kubectl apply -f gcp-minio-ha-r2.yml

# Wait for MinIO pods to be ready
kubectl wait --for=condition=ready pod -l app=minio -n minio --timeout=300s

# Verify deployment
kubectl get pods -n minio
kubectl get pvc -n minio
```

### Step 6: Deploy Trino with HTTPS & Auth

```bash
# Apply Trino configuration
kubectl apply -f gcp-trino-https-auth.yml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=300s

# Verify deployment
kubectl get pods -n trino
kubectl get svc -n trino
```

### Step 7: Get Load Balancer External IP

```bash
# Get Trino external service IP
kubectl get svc trino-external -n trino -w

# Wait for EXTERNAL-IP to be assigned (2-3 minutes)
```

The external IP will be used to access Trino from outside the cluster.

## Accessing the Platform

### From Bastion Host

**Trino CLI:**
```bash
# SSH to bastion
gcloud compute ssh aichemy-bastion --zone=europe-west1-b --tunnel-through-iap

# Install Docker (if not installed)
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
newgrp docker

# Get external IP
TRINO_IP=$(kubectl get svc trino-external -n trino -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Connect with authentication
docker run -it --rm trinodb/trino:latest trino \
  --server https://${TRINO_IP}:8443 \
  --user admin \
  --password \
  --insecure
```

### From Local Machine (Port Forwarding via Bastion)

**Set up SSH tunnel:**
```bash
# On local machine
gcloud compute ssh aichemy-bastion \
  --zone=europe-west1-b \
  --tunnel-through-iap \
  -- -L 8443:$(kubectl get svc trino-external -n trino -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8443
```

**Connect to Trino:**
```bash
# In another terminal on local machine
docker run -it --rm --network host trinodb/trino:latest trino \
  --server https://localhost:8443 \
  --user admin \
  --password \
  --insecure
```

### Python Client

```python
import urllib3
from trino.dbapi import connect
from trino.auth import BasicAuthentication

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Replace with your external IP
TRINO_IP = "<EXTERNAL-IP>"

conn = connect(
    host=TRINO_IP,
    port=8443,
    user='admin',
    http_scheme='https',
    auth=BasicAuthentication('admin', 'admin123'),
    verify=False
)

cur = conn.cursor()
cur.execute('SHOW CATALOGS')
print(cur.fetchall())
```

### MinIO Console

**Via Port Forward (from bastion):**
```bash
# On bastion
kubectl port-forward -n minio svc/minio-console 9001:9001

# Then setup SSH tunnel from local machine
gcloud compute ssh aichemy-bastion \
  --zone=europe-west1-b \
  --tunnel-through-iap \
  -- -L 9001:localhost:9001
```

Access at: http://localhost:9001
- Username: `admin`
- Password: `password123`

## Example Queries

### Iceberg Table
```sql
-- Create schema
CREATE SCHEMA iceberg.ic_test;

-- Create table
CREATE TABLE iceberg.ic_test.orders (
    order_id INTEGER,
    customer_id INTEGER,
    order_date DATE,
    amount DECIMAL(10,2)
);

-- Insert data
INSERT INTO iceberg.ic_test.orders VALUES 
    (1, 101, DATE '2025-01-15', 99.99),
    (2, 102, DATE '2025-01-16', 149.50);

-- Query
SELECT * FROM iceberg.ic_test.orders;
```

### Lance Vector Embeddings
```sql
-- Create schema
CREATE SCHEMA lance.ln_test;

-- Create embeddings table
CREATE TABLE lance.ln_test.embeddings (
    id INTEGER,
    document_name VARCHAR,
    content VARCHAR,
    embedding ARRAY(DOUBLE),
    metadata MAP(VARCHAR, VARCHAR),
    created_at TIMESTAMP
);

-- Insert vector data
INSERT INTO lance.ln_test.embeddings VALUES
(1, 'doc1.txt', 'Sample text about AI', 
 ARRAY[0.1, 0.2, 0.3, 0.4, 0.5],
 MAP(ARRAY['category', 'language'], ARRAY['tech', 'en']),
 CURRENT_TIMESTAMP);

-- Calculate dot product similarity
WITH vec1 AS (
    SELECT embedding as v1 FROM lance.ln_test.embeddings WHERE id = 1
),
vec2 AS (
    SELECT embedding as v2 FROM lance.ln_test.embeddings WHERE id = 2
)
SELECT 
    REDUCE(
        TRANSFORM(SEQUENCE(1, CARDINALITY(v1)), i -> v1[i] * v2[i]),
        0.0, (s, x) -> s + x, s -> s
    ) as dot_product
FROM vec1, vec2;
```

## Security Considerations

### Production Recommendations

⚠️ **The current setup uses self-signed certificates and default credentials. For production:**

1. **Replace Self-Signed Certificates**
   - Use Google-managed SSL certificates
   - Configure HTTPS Load Balancer with managed certificate
   - Update Trino configuration to use valid certificates

2. **Update Credentials**
   - Change MinIO access/secret keys
   - Update PostgreSQL password
   - Rotate Trino shared secret
   - Use bcrypt to generate new user passwords:
     ```bash
     docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 username password
     ```

3. **Enable Network Policies**
   - Restrict pod-to-pod communication
   - Implement egress filtering

4. **Use Secret Manager**
   - Store credentials in Google Secret Manager
   - Use Workload Identity to access secrets
   - Implement secret rotation

5. **Enable Audit Logging**
   - Configure Cloud Logging for GKE
   - Enable VPC Flow Logs
   - Configure Trino query logging

6. **Harden IAM Policies**
   - Apply principle of least privilege
   - Use Workload Identity for GCP service authentication
   - Enable Binary Authorization for container security

7. **Private Cluster Hardening**
   - Remove public endpoint access
   - Use Private Google Access
   - Implement VPC Service Controls

## Monitoring and Observability

### Cloud Logging

**View Trino logs:**
```bash
# From Cloud Console
gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=trino" --limit 50

# Or via kubectl
kubectl logs -n trino -l component=coordinator -f
kubectl logs -n trino -l component=worker -f
```

### Cloud Monitoring

**Create alerts:**
- Pod CPU/Memory usage
- Persistent Disk utilization
- Load Balancer health checks
- GKE node health

### Logs from Bastion

```bash
# Trino coordinator logs
kubectl logs -n trino -l component=coordinator -f

# Trino worker logs
kubectl logs -n trino -l component=worker -f

# Hive Metastore logs
kubectl logs -n trino -l app=hive-metastore -f

# MinIO logs
kubectl logs -n minio -l app=minio -f
```

## Troubleshooting

### Cannot Connect to Bastion

```bash
# Ensure IAP is enabled
gcloud services enable iap.googleapis.com

# Verify firewall rule for IAP
gcloud compute firewall-rules list --filter="name~iap"

# Connect with verbose output
gcloud compute ssh aichemy-bastion \
  --zone=europe-west1-b \
  --tunnel-through-iap \
  --verbosity=debug
```

### kubectl Connection Issues

```bash
# On bastion, verify gke-gcloud-auth-plugin
which gke-gcloud-auth-plugin

# If missing, install
sudo apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin

# Reconfigure kubectl
gcloud container clusters get-credentials ${CLUSTER_NAME} \
  --region=${REGION} \
  --internal-ip

# Test connection
kubectl get nodes -v=8
```

### Trino Pods Not Starting

```bash
# Check pod status
kubectl get pods -n trino
kubectl describe pod <pod-name> -n trino

# Check init container logs
kubectl logs <pod-name> -c generate-keystore -n trino

# Check events
kubectl get events -n trino --sort-by='.lastTimestamp'
```

### MinIO Pods Not Ready

```bash
# Check PVC status
kubectl get pvc -n minio
kubectl describe pvc <pvc-name> -n minio

# Verify storage class
kubectl get sc

# Check MinIO logs
kubectl logs minio-0 -n minio
```

### Load Balancer Not Getting External IP

```bash
# Check service
kubectl describe svc trino-external -n trino

# Verify quota
gcloud compute project-info describe --project=${PROJECT_ID}

# Check firewall rules for health checks
gcloud compute firewall-rules list --filter="name~health"
```

## Cost Optimization

### Resource Management
- Use preemptible nodes for non-critical workloads
- Enable cluster autoscaling
- Configure pod disruption budgets
- Use committed use discounts for long-term workloads

### Storage Optimization
- Use standard persistent disks for cold data
- Enable MinIO lifecycle policies
- Implement data compaction for Iceberg tables
- Use Cloud Storage lifecycle management

### Monitoring Costs
```bash
# View current costs
gcloud billing accounts list
gcloud billing projects describe ${PROJECT_ID}

# Set budget alerts in Cloud Console
```

## Backup and Disaster Recovery

### PostgreSQL Backup

```bash
# Exec into PostgreSQL pod
kubectl exec -it postgres-0 -n trino -- bash

# Create backup
pg_dump -U hive metastore > /tmp/metastore-backup.sql

# Copy backup to Cloud Storage
kubectl cp trino/postgres-0:/tmp/metastore-backup.sql ./metastore-backup.sql
gsutil cp metastore-backup.sql gs://${PROJECT_ID}-backups/
```

### MinIO Backup
- Use `mc mirror` to replicate to Cloud Storage
- Configure MinIO replication to another region
- Enable versioning on critical buckets

### Cluster Backup
```bash
# Backup GKE configuration
gcloud container clusters describe ${CLUSTER_NAME} \
  --region=${REGION} \
  --format=yaml > cluster-config.yaml

# Backup all Kubernetes resources
kubectl get all --all-namespaces -o yaml > k8s-resources.yaml
```

## Cleanup

### Delete Deployments

```bash
# Delete Trino
kubectl delete -f gcp-trino-https-auth.yml

# Delete MinIO
kubectl delete -f gcp-minio-ha-r2.yml

# Delete namespaces
kubectl delete namespace trino
kubectl delete namespace minio
```

### Delete GKE Cluster

```bash
# Delete cluster
gcloud container clusters delete ${CLUSTER_NAME} \
  --region=${REGION} \
  --quiet
```

### Delete Network Infrastructure

```bash
# Delete bastion
gcloud compute instances delete aichemy-bastion \
  --zone=europe-west1-b \
  --quiet

# Delete firewall rules
gcloud compute firewall-rules delete \
  ${NETWORK_NAME}-allow-internal \
  ${NETWORK_NAME}-allow-iap-ssh \
  ${NETWORK_NAME}-allow-health-checks \
  ${NETWORK_NAME}-allow-trino \
  ${NETWORK_NAME}-allow-bastion-to-gke \
  --quiet

# Delete Cloud NAT
gcloud compute routers nats delete ${NETWORK_NAME}-nat \
  --router=${NETWORK_NAME}-router \
  --region=${REGION} \
  --quiet

# Delete Cloud Router
gcloud compute routers delete ${NETWORK_NAME}-router \
  --region=${REGION} \
  --quiet

# Delete subnets
gcloud compute networks subnets delete ${SUBNET_PUBLIC} \
  --region=${REGION} \
  --quiet

gcloud compute networks subnets delete ${SUBNET_PRIVATE} \
  --region=${REGION} \
  --quiet

# Delete VPC
gcloud compute networks delete ${NETWORK_NAME} --quiet
```

## GCP-Specific Features

### Workload Identity

Enable Workload Identity for pods to access GCP services:

```bash
# Create GCP service account
gcloud iam service-accounts create trino-sa \
  --display-name="Trino Service Account"

# Grant permissions (e.g., for Cloud Storage access)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:trino-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

# Bind to Kubernetes service account
gcloud iam service-accounts add-iam-policy-binding \
  trino-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[trino/trino-coordinator]"

# Annotate K8s service account
kubectl annotate serviceaccount trino-coordinator \
  -n trino \
  iam.gke.io/gcp-service-account=trino-sa@${PROJECT_ID}.iam.gserviceaccount.com
```

### Cloud Armor (WAF)

Protect load balancers with Cloud Armor:

```bash
# Create security policy
gcloud compute security-policies create trino-armor \
  --description "Protection for Trino"

# Add rate limiting rule
gcloud compute security-policies rules create 1000 \
  --security-policy trino-armor \
  --action=rate-based-ban \
  --rate-limit-threshold-count=100 \
  --rate-limit-threshold-interval-sec=60 \
  --ban-duration-sec=600

# Attach to backend service (after creating HTTPS LB)
```

### Private Google Access

Already enabled in the infrastructure setup - allows private nodes to access Google APIs without external IPs.

## Support and Documentation

- **Trino Documentation**: https://trino.io/docs/current/
- **MinIO Documentation**: https://min.io/docs/minio/kubernetes/upstream/
- **GKE Documentation**: https://cloud.google.com/kubernetes-engine/docs
- **GCP VPC**: https://cloud.google.com/vpc/docs

### Additional Notes Files
- See [gcp-trino-notes.md](gcp-trino-notes.md) for operational commands and query examples
- See [gcp-infra_notes.md](gcp-infra_notes.md) for infrastructure notes
- See [gcp-minio-notes.md](gcp-minio-notes.md) for MinIO-specific operations

## License

See [LICENSE](../LICENCE) file in the root directory.
