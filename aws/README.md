# AIchemy AWS Architecture

This directory contains the infrastructure and deployment configurations for running the AIchemy data lakehouse platform on AWS EKS (Elastic Kubernetes Service).

## Architecture Overview

The AIchemy platform provides a complete data lakehouse solution with support for multiple table formats (Hive, Iceberg, Delta Lake, Lance) running on Kubernetes with Trino as the query engine and MinIO as S3-compatible storage.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          AWS Cloud - VPC                                │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    EKS Cluster (Private Subnets)                 │   │
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
│  │  │           │  • Storage: EBS (gp2) │                        │  │   │
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
│  │  │            │ EBS Volumes    │                              │  │   │
│  │  │            │ (4x 10Gi gp2)  │                              │  │   │
│  │  │            └────────────────┘                              │  │   │
│  │  └────────────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                    External Access                               │   │
│  │                                                                  │   │
│  │  ┌────────────────────┐         ┌────────────────────┐           │   │
│  │  │ ELB Classic LB     │         │ ELB Classic LB     │           │   │
│  │  │ (Trino External)   │         │ (MinIO Console)    │           │   │
│  │  │                    │         │                    │           │   │
│  │  │ • HTTPS :8443      │         │ • API :9000        │           │   │
│  │  │ • HTTP  :8080      │         │ • Console :9001    │           │   │
│  │  └────────────────────┘         └────────────────────┘           │   │
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
- 4 EBS volumes (gp2 storage class)
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
- 10Gi EBS volume (gp2 storage class)
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

## Infrastructure Setup

The infrastructure is provisioned using a series of shell scripts:

### 1. `aws-0-infra.sh` - VPC and Network Setup
- Creates VPC, subnets (public/private)
- Configures NAT Gateway for private subnet internet access
- Sets up route tables

### 2. `aws-1-iam.sh` - IAM Roles and Policies
- Creates EKS cluster IAM role
- Sets up node group IAM role
- Configures necessary AWS service policies

### 3. `aws-2-eks.sh` - EKS Cluster Creation
- Creates EKS cluster in private subnets
- Configures cluster security groups
- Enables cluster logging

### 4. `aws-3-iam-ng.sh` - Node Group IAM Configuration
- Creates IAM role for EKS node groups
- Attaches required policies (EKS, ECR, CNI)

### 5. `aws-4-ng.sh` - Node Group Deployment
- Creates managed node groups
- Configures instance types and scaling
- Attaches to private subnets

### 6. `aws-5-bastion.sh` - Bastion Host Setup
- Creates bastion host in public subnet
- Configures security groups for cluster access
- Enables SSH access via bastion

### 7. `aws-fix-ebs-csi.sh` - EBS CSI Driver
- Installs AWS EBS CSI driver addon
- Configures IAM roles for service accounts (IRSA)
- Enables dynamic volume provisioning

## Storage Classes

### gp2 (General Purpose SSD)
```yaml
storageClassName: "gp2"
```
- Used for PostgreSQL and MinIO persistent volumes
- AWS EBS General Purpose SSD
- 3 IOPS per GB baseline performance

## Deployment Instructions

### Prerequisites
1. AWS CLI configured with appropriate credentials
2. kubectl installed
3. eksctl (optional, for easier cluster management)

### Step 1: Infrastructure Setup
```bash
# Run scripts in order
cd aws
./aws-0-infra.sh
./aws-1-iam.sh
./aws-2-eks.sh
./aws-3-iam-ng.sh
./aws-4-ng.sh
./aws-5-bastion.sh
./aws-fix-ebs-csi.sh
```

### Step 2: Configure kubectl
```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
```

### Step 3: Deploy MinIO
```bash
kubectl apply -f aws-minio-ha.yml
```

Verify MinIO deployment:
```bash
kubectl get pods -n minio
kubectl get pvc -n minio
```

### Step 4: Deploy Trino with HTTPS & Auth
```bash
kubectl apply -f aws-trino-https-auth.yml
```

Verify Trino deployment:
```bash
kubectl get pods -n trino
kubectl get svc -n trino
```

### Step 5: Get Load Balancer Endpoint
```bash
kubectl get svc trino-external -n trino
```

Wait for the EXTERNAL-IP to be assigned (AWS ELB provisioning takes 2-3 minutes).

## Accessing the Platform

### Trino CLI (Docker)
```bash
docker run -it --rm trinodb/trino:latest trino \
  --server https://<ELB-ENDPOINT>:8443 \
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

conn = connect(
    host='<ELB-ENDPOINT>',
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
```bash
# Port forward to access console
kubectl port-forward -n minio svc/minio-console 9001:9001
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
   - Use AWS Certificate Manager (ACM) for valid TLS certificates
   - Configure Application Load Balancer with ACM certificate
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

4. **Use AWS Secrets Manager**
   - Store credentials in Secrets Manager
   - Use External Secrets Operator to sync to Kubernetes

5. **Enable Audit Logging**
   - Configure CloudWatch logging for EKS
   - Enable VPC Flow Logs
   - Configure Trino query logging

6. **Harden IAM Policies**
   - Apply principle of least privilege
   - Use IRSA (IAM Roles for Service Accounts)
   - Enable MFA for critical operations

## Monitoring and Observability

### Logs
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

### Health Checks
```bash
# Check all pods
kubectl get pods -A

# Check Trino health
kubectl exec -n trino deployment/trino-coordinator -- \
  curl -s http://localhost:8080/v1/info

# Check MinIO health
kubectl exec -n minio minio-0 -- \
  curl -s http://localhost:9000/minio/health/live
```

## Troubleshooting

### Trino Coordinator Not Starting
```bash
# Check logs for errors
kubectl logs -n trino deployment/trino-coordinator

# Check init container logs
kubectl logs -n trino <pod-name> -c generate-keystore

# Verify ConfigMaps
kubectl get configmap -n trino
kubectl describe configmap trino-coordinator -n trino
```

### MinIO Pods Not Ready
```bash
# Check PVC status
kubectl get pvc -n minio

# Describe PVC for events
kubectl describe pvc -n minio

# Verify storage class
kubectl get sc
```

### Cannot Connect to PostgreSQL
```bash
# Test connection from Hive Metastore
kubectl exec -n trino deployment/hive-metastore -- \
  nc -zv postgres 5432

# Check PostgreSQL logs
kubectl logs -n trino statefulset/postgres
```

## Cost Optimization

### Resource Scaling
- Reduce worker replicas during low-usage periods
- Use spot instances for worker nodes
- Enable cluster autoscaling

### Storage Optimization
- Configure MinIO lifecycle policies
- Use S3 Intelligent-Tiering for long-term data
- Implement data compaction for Iceberg tables

## Backup and Disaster Recovery

### PostgreSQL Backup
```bash
# Exec into PostgreSQL pod
kubectl exec -it postgres-0 -n trino -- bash

# Create backup
pg_dump -U hive metastore > /tmp/metastore-backup.sql

# Copy backup to local
kubectl cp trino/postgres-0:/tmp/metastore-backup.sql ./metastore-backup.sql
```

### MinIO Backup
- Use `mc mirror` command to replicate buckets
- Configure MinIO replication to another region
- Enable versioning on critical buckets

## Support and Documentation

- **Trino Documentation**: https://trino.io/docs/current/
- **MinIO Documentation**: https://min.io/docs/minio/kubernetes/upstream/
- **Apache Hive Metastore**: https://hive.apache.org/
- **AWS EKS Documentation**: https://docs.aws.amazon.com/eks/

## License

See [LICENSE](../LICENCE) file in the root directory.
