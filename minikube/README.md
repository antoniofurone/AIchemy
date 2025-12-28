# AIchemy Minikube Architecture

This directory contains the infrastructure and deployment configurations for running the AIchemy data lakehouse platform on Minikube for local development and testing.

## Architecture Overview

The AIchemy platform provides a complete data lakehouse solution with support for multiple table formats (Hive, Iceberg, Delta Lake, Lance) running on Kubernetes with Trino as the query engine and MinIO as S3-compatible storage.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Minikube Single-Node Cluster                             │
│                           (Local Development)                                   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              Kafka Namespace (Optional - Streaming)                      │   │
│  │                                                                          │   │
│  │  ┌────────────────┐         ┌────────────────┐      ┌──────────────┐     │   │
│  │  │ Kafka Broker-0 │◄───────►│ Kafka Broker-1 │      │  Kafka UI    │     │   │
│  │  │  (KRaft Mode)  │         │  (KRaft Mode)  │      │              │     │   │
│  │  │                │         │                │      │  • Port:8080 │     │   │
│  │  │ • Broker :9092 │         │ • Broker :9092 │      │  • NP: 30081 │     │   │
│  │  │ • Control:9093 │         │ • Control:9093 │      └──────────────┘     │   │
│  │  │ • Storage: 5Gi │         │ • Storage: 5Gi │                           │   │
│  │  └────────────────┘         └────────────────┘                           │   │
│  │                                                                          │   │
│  │  NodePort: 30092 → 9092 (External access)                                │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              Flink Namespace (Optional - Stream Processing)              │   │
│  │                                                                          │   │
│  │  ┌───────────────────────────────────────────────┐                       │   │
│  │  │  Flink Kubernetes Operator                    │                       │   │
│  │  │                                               │                       │   │
│  │  │  • Manages FlinkDeployment CRDs               │                       │   │
│  │  │  • Dynamic JobManager/TaskManager scaling     │                       │   │
│  │  │  • Checkpoint & Savepoint management          │                       │   │
│  │  └───────────────────────────────────────────────┘                       │   │
│  │              │                                                           │   │
│  │              ▼  (Deploys on-demand)                                      │   │
│  │  ┌──────────────────┐         ┌──────────────────┐                       │   │
│  │  │  JobManager      │◄───────►│  TaskManager     │                       │   │
│  │  │  (Session/Job)   │         │  (2+ replicas)   │                       │   │
│  │  │                  │         │                  │                       │   │
│  │  │  • RPC :6123     │         │  • Slots: 2      │                       │   │
│  │  │  • Web :8081     │         │  • Memory: 1Gi   │                       │   │
│  │  └──────────────────┘         └──────────────────┘                       │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              Flowise Namespace (Optional - AI Workflows)                 │   │
│  │                                                                          │   │
│  │  ┌──────────────────┐         ┌──────────────────┐                       │   │
│  │  │  Flowise Server  │◄───────►│  PostgreSQL 15   │                       │   │
│  │  │                  │         │                  │                       │   │
│  │  │  • Port: 3000    │         │  • Port: 5432    │                       │   │
│  │  │  • NP: 30300     │         │  • DB: flowise   │                       │   │
│  │  │  • Auth: admin   │         │  • Storage: 10Gi │                       │   │
│  │  │  • Storage: 5Gi  │         └──────────────────┘                       │   │
│  │  │                  │                                                    │   │
│  │  │  • LLM Chains    │                                                    │   │
│  │  │  • Vector DBs    │                                                    │   │
│  │  │  • Workflows API │                                                    │   │
│  │  └──────────────────┘                                                    │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              Trino Namespace (Query Engine)                              │   │
│  │                                                                          │   │
│  │  ┌─────────────────┐         ┌─────────────────┐                         │   │
│  │  │ Trino Coord.    │         │ Trino Worker    │                         │   │
│  │  │ (1 replica)     │◄───────►│ (2 replicas)    │                         │   │
│  │  │                 │         │                 │                         │   │
│  │  │ • HTTP :8080    │         │ • HTTP :8080    │                         │   │
│  │  │ • HTTPS :8443   │         │ • HTTPS :8443   │                         │   │
│  │  │ • Auth: Password│         │ • Shared Secret │                         │   │
│  │  └────────┬────────┘         └────────┬────────┘                         │   │
│  │           │                           │                                  │   │
│  │           └───────────┬───────────────┘                                  │   │
│  │                       │                                                  │   │
│  │                       ▼                                                  │   │
│  │           ┌───────────────────────┐                                      │   │
│  │           │  Hive Metastore       │                                      │   │
│  │           │  (1 replica)          │                                      │   │
│  │           │                       │                                      │   │
│  │           │  • Thrift :9083       │                                      │   │
│  │           │  • S3 Support         │                                      │   │
│  │           └───────────┬───────────┘                                      │   │
│  │                       │                                                  │   │
│  │                       ▼                                                  │   │
│  │           ┌───────────────────────┐                                      │   │
│  │           │  PostgreSQL           │                                      │   │
│  │           │  (StatefulSet)        │                                      │   │
│  │           │                       │                                      │   │
│  │           │  • Port :5432         │                                      │   │
│  │           │  • Storage: emptyDir  │                                      │   │
│  │           └───────────────────────┘                                      │   │
│  │                                                                          │   │
│  │  ┌────────────────────────────────────────────────┐                      │   │
│  │  │           NodePort Services                    │                      │   │
│  │  │                                                │                      │   │
│  │  │  • Trino HTTPS: 30443 → 8443                   │                      │   │
│  │  │  • Trino HTTP:  30080 → 8080                   │                      │   │
│  │  └────────────────────────────────────────────────┘                      │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │              MinIO Namespace (Object Storage - HA)                       │   │
│  │                                                                          │   │
│  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                                  │   │
│  │  │MinIO │  │MinIO │  │MinIO │  │MinIO │                                  │   │
│  │  │Pod-0 │  │Pod-1 │  │Pod-2 │  │Pod-3 │                                  │   │
│  │  │      │  │      │  │      │  │      │                                  │   │
│  │  │:9000 │  │:9000 │  │:9000 │  │:9000 │                                  │   │
│  │  │:9001 │  │:9001 │  │:9001 │  │:9001 │                                  │   │
│  │  └───┬──┘  └───┬──┘  └───┬──┘  └───┬──┘                                  │   │
│  │      │         │         │         │                                     │   │
│  │      └─────────┴─────────┴─────────┘                                     │   │
│  │                    │                                                     │   │
│  │            ┌───────▼────────┐                                            │   │
│  │            │ PersistentVols │                                            │   │
│  │            │ (4x 10Gi)      │                                            │   │
│  │            └────────────────┘                                            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                    Local Access                                          │   │
│  │                                                                          │   │
│  │  Port Forwarding:                                                        │   │
│  │  • kubectl port-forward -n kafka svc/kafka-ui 8080:8080                  │   │
│  │  • kubectl port-forward -n flowise svc/flowise 3000:3000                 │   │
│  │  • kubectl port-forward -n trino svc/trino 8443:8443                     │   │
│  │  • kubectl port-forward -n minio svc/minio-console 9001:9001             │   │
│  │                                                                          │   │
│  │  Minikube Service (NodePort):                                            │   │
│  │  • minikube service kafka-ui -n kafka --url          (30081)             │   │
│  │  • minikube service flowise -n flowise --url         (30300)             │   │
│  │  • minikube service trino-nodeport -n trino --url    (30443/30080)       │   │
│  │  • minikube service minio-console -n minio --url     (9001)              │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │                    Data Flow                                             │   │
│  │                                                                          │   │
│  │  Producer → Kafka → Flink → Trino → MinIO                                │   │
│  │              ▲       │       ▲       ▲                                   │   │
│  │              │       │       │       │                                   │   │
│  │              │       └───────┘       │                                   │   │
│  │              │                       │                                   │   │
│  │           Flowise ───────────────────┘                                   │   │
│  │         (AI Workflows & Vector Processing)                               │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Apache Kafka (Streaming Platform)

**Purpose**: Distributed event streaming platform for real-time data pipelines and streaming applications

**Architecture**:
- **KRaft Mode**: No Zookeeper dependency (Kafka 3.8.1+)
- **Brokers**: 2 replicas with combined broker/controller roles
- **HA Configuration**: High availability with replication factor 2

**Features**:
- **Auto-topic creation** enabled
- **Replication**: Factor 2 for fault tolerance
- **Retention**: 7 days (168 hours)
- **NodePort Access**: Port 30092 for external clients

**UI Management**:
- **Kafka UI**: Web interface for cluster monitoring and management
- **Port**: 8080 (NodePort 30081)

**Resources**:
- Request: 512Mi RAM, 250m CPU per broker
- Limit: 1Gi RAM, 500m CPU per broker
- Storage: 5Gi per broker (persistent volumes)

**Access**:
- Internal: `kafka-0.kafka-headless.kafka.svc.cluster.local:9092`
- NodePort: `<minikube-ip>:30092`

### 2. Apache Flink Operator

**Purpose**: Kubernetes operator for deploying and managing Apache Flink clusters

**Architecture**:
- **Flink Operator**: Manages FlinkDeployment custom resources
- **Session Mode**: Long-running cluster for multiple jobs
- **Native Kubernetes Integration**: Dynamic resource allocation

**Capabilities**:
- **Job Management**: Deploy, update, and monitor Flink jobs
- **HA Support**: Kubernetes-based high availability
- **Checkpointing**: Automatic state management
- **Savepoints**: Manual state snapshots for upgrades

**Typical Deployment**:
- **JobManager**: 1 replica, 1Gi memory, 1 CPU
- **TaskManager**: 2 replicas, 1Gi memory, 1 CPU each
- **Task Slots**: 2 per TaskManager

**Features**:
- Docker-in-Docker support for Python SDK jobs
- Beam integration for unified batch/streaming
- State backends: filesystem, RocksDB
- Metrics and monitoring integration

### 3. Flowise (Low-Code AI Orchestration)

**Purpose**: Visual builder for AI workflows and LangChain applications

**Architecture**:
- **Flowise Server**: Node.js application with web UI
- **PostgreSQL**: Persistent storage for workflows and configs
- **Persistent Storage**: 5Gi for application data

**Features**:
- **Visual Flow Builder**: Drag-and-drop interface for AI chains
- **LLM Integration**: OpenAI, Anthropic, local models
- **Vector Stores**: Support for embeddings and retrieval
- **API Deployment**: Auto-generate APIs from flows

**Credentials**:
- Username: `admin`
- Password: `admin123`

**Database**:
- PostgreSQL 15
- Database: `flowise`
- Storage: 10Gi persistent volume

**Resources**:
- Flowise: 512Mi-2Gi RAM, 500m-1000m CPU
- PostgreSQL: 256Mi-512Mi RAM, 250m-500m CPU

**Access**:
- Web UI: Port 3000 (NodePort 30300)
- Healthz: `/healthz` endpoint

### 4. Trino Query Engine

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
- Request: 2Gi RAM, 1 CPU per pod
- Limit: 4Gi RAM, 2 CPU per pod

**Access**:
- NodePort 30443 (HTTPS) - requires authentication
- NodePort 30080 (HTTP) - internal use

### 5. MinIO Object Storage (HA)

**Purpose**: S3-compatible object storage for data lake files

**Architecture**:
- 4-node distributed deployment with erasure coding
- Tolerates up to 2 node failures
- StatefulSet with persistent storage

**Storage**:
- 4 Persistent Volumes (default storage class)
- 10Gi per volume (40Gi total)

**Endpoints**:
- API: port 9000
- Console: port 9001

**Credentials**:
- Access Key: `admin`
- Secret Key: `password123`

### 6. Hive Metastore

**Purpose**: Centralized metadata catalog for all table formats

**Features**:
- Stores table schemas, partitions, and locations
- Connects to PostgreSQL for metadata persistence
- S3-compatible storage support via Hadoop AWS libraries

**Dependencies**:
- PostgreSQL JDBC driver (auto-downloaded at startup)
- Hadoop AWS + AWS SDK bundles (auto-downloaded at startup)

### 7. PostgreSQL Database

**Purpose**: Persistent metadata storage for Hive Metastore

**Configuration**:
- Database: `metastore`
- User: `hive`
- Password: `hivepassword`

**Storage**:
- emptyDir (non-persistent - data lost on pod restart)
- For production, upgrade to PersistentVolume

## Data Flow

1. **Client Query** → Trino Coordinator (HTTPS :8443 via port-forward or NodePort)
2. **Query Planning** → Coordinator distributes tasks to Workers
3. **Metadata Lookup** → Workers query Hive Metastore (Thrift :9083)
4. **Metastore Query** → PostgreSQL database (:5432)
5. **Data Read/Write** → MinIO S3 API (:9000)
6. **Results** → Aggregated and returned to client

## Network Communication

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Local Browser | Trino Coordinator | 8443 | HTTPS | User queries (password auth) |
| Local Browser | Trino Coordinator | 8080 | HTTP | Internal testing |
| Coordinator | Workers | 8080 | HTTP | Internal communication (shared secret) |
| Trino | Hive Metastore | 9083 | Thrift | Metadata operations |
| Hive Metastore | PostgreSQL | 5432 | TCP | Metadata storage |
| Trino/Metastore | MinIO | 9000 | HTTP | S3 object storage |
| Local Browser | MinIO Console | 9001 | HTTP | MinIO administration |

## Prerequisites

### Required Software
- **Minikube** >= 1.30.0
- **kubectl** >= 1.27.0
- **Docker** or **VirtualBox** (as Minikube driver)
- **Minimum System Requirements**:
  - 8GB RAM (16GB recommended)
  - 4 CPU cores
  - 40GB free disk space

### Installation

#### Windows
```powershell
# Install Minikube
choco install minikube

# Install kubectl
choco install kubernetes-cli

# Verify installation
minikube version
kubectl version --client
```

#### macOS
```bash
# Install Minikube
brew install minikube

# Install kubectl
brew install kubectl

# Verify installation
minikube version
kubectl version --client
```

#### Linux
```bash
# Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
minikube version
kubectl version --client
```

## Deployment Instructions

### Step 1: Start Minikube

```bash
# Start Minikube with sufficient resources
minikube start --cpus=4 --memory=8192 --disk-size=40g

# Verify cluster is running
minikube status
kubectl cluster-info
```

### Step 2: Configure kubectl Context

```bash
# Update context to Minikube
minikube update-context

# Verify context
kubectl config get-contexts
kubectl config use-context minikube
```

### Step 3: Deploy Kafka (Optional - for streaming)

```bash
# Apply Kafka HA configuration
kubectl apply -f mk-kafka-ha.yml

# Wait for Kafka brokers to be ready
kubectl wait --for=condition=ready pod -l app=kafka -n kafka --timeout=300s

# Verify deployment
kubectl get pods -n kafka
kubectl get pvc -n kafka

# Access Kafka UI
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
# Open http://localhost:8080
```

### Step 4: Deploy Flink Operator (Optional - for stream processing)

```bash
# Install Flink Kubernetes Operator using Helm
helm repo add flink-operator-repo https://downloads.apache.org/flink/flink-kubernetes-operator-1.8.0/
helm repo update

# Install operator
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
  --namespace flink --create-namespace

# Verify operator is running
kubectl get pods -n flink

# Deploy a Basic Example
kubectl create -f https://raw.githubusercontent.com/apache/flink-kubernetes-operator/release-1.13/examples/basic.yaml

# Deploy a Flink session cluster (see flink deployment examples in python/beam-flink-test/)
```

### Step 5: Deploy Flowise (Optional - for AI workflows)

```bash
# Apply Flowise configuration
kubectl apply -f mk-flowise.yml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=flowise -n flowise --timeout=300s

# Verify deployment
kubectl get pods -n flowise
kubectl get pvc -n flowise

# Access Flowise UI
kubectl port-forward -n flowise svc/flowise 3000:3000
# Open http://localhost:3000
# Login: admin / admin123
```

### Step 6: Deploy MinIO (HA)

```bash
# Apply MinIO HA configuration
kubectl apply -f mk-minio-ha-r2.yml

# Wait for MinIO pods to be ready
kubectl wait --for=condition=ready pod -l app=minio -n minio --timeout=300s

# Verify deployment
kubectl get pods -n minio
kubectl get pvc -n minio
```

### Step 7: Deploy Trino with HTTPS & Authentication

```bash
# Apply Trino configuration
kubectl apply -f mk-trino-https-auth.yml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=300s

# Verify deployment
kubectl get pods -n trino
kubectl get svc -n trino
```

### Step 8: Access Services

#### Option A: Port Forwarding (Recommended)

**Kafka UI:**
```bash
kubectl port-forward -n kafka svc/kafka-ui 8080:8080
```
Access at: http://localhost:8080

**Flowise:**
```bash
kubectl port-forward -n flowise svc/flowise 3000:3000
```
Access at: http://localhost:3000
- Login: `admin` / `admin123`

**Trino HTTPS:**
```bash
kubectl port-forward -n trino svc/trino 8443:8443
```
Access at: https://localhost:8443

**Trino HTTP:**
```bash
kubectl port-forward -n trino svc/trino 8080:8080
```
Access at: http://localhost:8080

**MinIO Console:**
```bash
kubectl port-forward -n minio svc/minio-console 9001:9001
```
Access at: http://localhost:9001

#### Option B: Minikube Service (NodePort)

**Kafka UI:**
```bash
minikube service kafka-ui -n kafka --url
```

**Flowise:**
```bash
minikube service flowise -n flowise --url
```

**Trino:**
```bash
minikube service trino-nodeport -n trino --url
```

**MinIO:**
```bash
minikube service minio-console -n minio --url
```

## Accessing the Platform

### Trino CLI (Direct from Coordinator Pod)

```bash
# Connect to coordinator pod
kubectl exec -it deployment/trino-coordinator -n trino -- trino

# Or with server specification
kubectl exec -it deployment/trino-coordinator -n trino -- trino --server localhost:8080
```

### Trino CLI (Docker Client)

```bash
# With HTTPS and authentication
docker run -it --rm --network host trinodb/trino:latest trino \
  --server https://localhost:8443 \
  --user admin \
  --password \
  --insecure

# Enter password when prompted: admin123
```

### Python Client

Create a file `trino_client.py`:

```python
import urllib3
from trino.dbapi import connect
from trino.auth import BasicAuthentication

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Connect to Trino
conn = connect(
    host='localhost',
    port=8443,
    user='admin',
    http_scheme='https',
    auth=BasicAuthentication('admin', 'admin123'),
    catalog='iceberg',
    schema='default',
    verify=False
)

# Execute query
cur = conn.cursor()
cur.execute('SHOW CATALOGS')
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()
```

Run with:
```bash
# Install dependencies
pip install trino urllib3

# Run script (ensure port-forward is active)
python trino_client.py
```

### MinIO Console

Access via browser at http://localhost:9001 (with port-forward active)

**Credentials:**
- Username: `admin`
- Password: `password123`

## Example Queries

### Kafka Producer/Consumer Examples

#### Python Producer
```python
from kafka import KafkaProducer
import json

# Get Minikube IP
# minikube_ip = $(minikube ip)

producer = KafkaProducer(
    bootstrap_servers=['<minikube-ip>:30092'],
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Send messages
for i in range(10):
    message = {'id': i, 'value': f'message-{i}'}
    producer.send('test-topic', message)
    print(f"Sent: {message}")

producer.flush()
producer.close()
```

#### Python Consumer
```python
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'test-topic',
    bootstrap_servers=['<minikube-ip>:30092'],
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest',
    group_id='my-group'
)

print("Waiting for messages...")
for message in consumer:
    print(f"Received: {message.value}")
```

#### Using kubectl exec (Inside cluster)
```bash
# Create topic
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --create --topic test-topic --partitions 2 --replication-factor 2 \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# List topics
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# Produce messages
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-producer.sh \
  --topic test-topic --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# Consume messages
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --topic test-topic --from-beginning \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092
```

### Flowise AI Workflow Examples

#### Access Flowise UI
1. Port-forward: `kubectl port-forward -n flowise svc/flowise 3000:3000`
2. Open browser: http://localhost:3000
3. Login with `admin` / `admin123`

#### Create a Simple LLM Chain
1. Click **"Add New"** chatflow
2. Drag **"ChatOpenAI"** from nodes panel
3. Add your OpenAI API key
4. Drag **"ConversationChain"** 
5. Connect ChatOpenAI → ConversationChain
6. Click **"Save"** then **"Start"**
7. Test in the chat panel

#### Using Flowise API
```python
import requests

# Get the API endpoint from Flowise UI after deploying a flow
FLOWISE_URL = "http://localhost:3000/api/v1/prediction/<flow-id>"

response = requests.post(
    FLOWISE_URL,
    json={
        "question": "What is machine learning?",
    }
)

print(response.json())
```

#### Vector Store Integration
1. Add **"Pinecone"** or **"Chroma"** node
2. Add **"OpenAI Embeddings"** node
3. Add **"Document Loader"** (PDF, CSV, etc.)
4. Connect: Document → Embeddings → Vector Store
5. Use with **"Retrieval QA Chain"** for RAG

### Show Available Catalogs
```sql
SHOW CATALOGS;
```

Expected output:
```
 Catalog 
---------
 delta   
 hive    
 iceberg 
 lance   
 system  
```

### Hive Tables

```sql
-- Create schema
CREATE SCHEMA hive.hs_test;

-- Verify
SHOW SCHEMAS IN hive;

-- Create table
CREATE TABLE hive.hs_test.users (
    id INTEGER,
    name VARCHAR,
    email VARCHAR
);

-- Insert data
INSERT INTO hive.hs_test.users VALUES 
    (1, 'Mario', 'mario@example.com');

-- Query
SELECT * FROM hive.hs_test.users;
```

### Iceberg Tables

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

### Delta Lake Tables

```sql
-- Create schema
CREATE SCHEMA delta.test_db;

-- Create table
CREATE TABLE delta.test_db.products (
    product_id INTEGER,
    product_name VARCHAR,
    price DECIMAL(10,2)
);

-- Insert data
INSERT INTO delta.test_db.products VALUES 
    (1, 'Laptop', 999.99),
    (2, 'Mouse', 29.99);

-- Query
SELECT * FROM delta.test_db.products;
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
 CURRENT_TIMESTAMP),
 
(2, 'doc2.txt', 'Machine learning basics',
 ARRAY[0.2, 0.3, 0.1, 0.5, 0.4],
 MAP(ARRAY['category', 'language'], ARRAY['tech', 'en']),
 CURRENT_TIMESTAMP),
 
(3, 'doc3.txt', 'Deep learning concepts',
 ARRAY[0.15, 0.25, 0.2, 0.45, 0.42],
 MAP(ARRAY['category', 'language'], ARRAY['ai', 'en']),
 CURRENT_TIMESTAMP);

-- Query embeddings
SELECT id, document_name, embedding 
FROM lance.ln_test.embeddings 
WHERE id = 1;

-- Calculate dot product similarity between vectors
WITH vec1 AS (
    SELECT embedding as v1 
    FROM lance.ln_test.embeddings 
    WHERE id = 1
),
vec2 AS (
    SELECT embedding as v2 
    FROM lance.ln_test.embeddings 
    WHERE id = 2
)
SELECT 
    REDUCE(
        TRANSFORM(
            SEQUENCE(1, CARDINALITY(v1)),
            i -> v1[i] * v2[i]
        ),
        0.0,
        (s, x) -> s + x,
        s -> s
    ) as dot_product
FROM vec1, vec2;

-- Query embeddings with specific values
SELECT id, document_name, embedding[1] as first_dimension
FROM lance.ln_test.embeddings
WHERE embedding[1] > 0.15;

-- Aggregate statistics on vectors
SELECT 
    AVG(embedding[1]) as avg_dim1,
    AVG(embedding[2]) as avg_dim2,
    COUNT(*) as total_vectors
FROM lance.ln_test.embeddings;
```

## Security Configuration

### Adding New Users

Generate password hash:
```bash
# Using Docker
docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 newuser newpassword

# Example output:
# newuser:$2y$10$abcdef123456...
```

Update the secret:
```bash
kubectl edit secret trino-password-db -n trino
```

Add the new user line to the `password.db` field.

Restart Trino:
```bash
kubectl rollout restart deployment/trino-coordinator -n trino
kubectl rollout restart deployment/trino-worker -n trino
```

### TLS Certificates

The current setup uses **self-signed certificates** generated at pod startup. For production or custom certificates:

1. Generate your certificates:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=trino.local"
```

2. Create Kubernetes secret:
```bash
kubectl create secret tls trino-tls-secret \
  --cert=tls.crt --key=tls.key -n trino
```

3. Update the deployment to use the secret instead of init container

## Monitoring and Logging

### View Logs

**Kafka Brokers:**
```bash
kubectl logs -n kafka kafka-0 -f
kubectl logs -n kafka kafka-1 -f
```

**Kafka UI:**
```bash
kubectl logs -n kafka -l app=kafka-ui -f
```

**Flowise:**
```bash
kubectl logs -n flowise -l app=flowise -f
```

**Flowise PostgreSQL:**
```bash
kubectl logs -n flowise -l app=postgres -f
```

**Trino Coordinator:**
```bash
kubectl logs -n trino -l component=coordinator -f
```

**Trino Workers:**
```bash
kubectl logs -n trino -l component=worker -f
```

**Hive Metastore:**
```bash
kubectl logs -n trino -l app=hive-metastore -f
```

**PostgreSQL:**
```bash
kubectl logs -n trino statefulset/postgres -f
```

**MinIO:**
```bash
kubectl logs -n minio -l app=minio -f
```

### Check Pod Status

```bash
# All namespaces
kubectl get pods -A

# Kafka namespace
kubectl get pods -n kafka

# Flowise namespace
kubectl get pods -n flowise

# Flink namespace (if deployed)
kubectl get pods -n flink

# Trino namespace
kubectl get pods -n trino

# MinIO namespace
kubectl get pods -n minio
```

### Describe Resources

```bash
# Describe pod for detailed information
kubectl describe pod <pod-name> -n trino

# Check events
kubectl get events -n trino --sort-by='.lastTimestamp'
```

## Troubleshooting

### Kafka Brokers Not Starting

**Check broker logs:**
```bash
kubectl logs kafka-0 -n kafka
kubectl logs kafka-1 -n kafka
```

**Check init container:**
```bash
kubectl logs kafka-0 -n kafka -c kafka-init
```

**Common issues:**
- Storage formatting failed (check PVC)
- Network communication between brokers
- Cluster ID mismatch
- Insufficient resources

**Reset Kafka cluster:**
```bash
kubectl delete statefulset kafka -n kafka
kubectl delete pvc -l app=kafka -n kafka
kubectl apply -f mk-kafka-ha.yml
```

### Flowise Not Connecting to Database

**Check PostgreSQL status:**
```bash
kubectl exec -it -n flowise deployment/postgres -- psql -U flowise -d flowise -c "\dt"
```

**Verify connection:**
```bash
kubectl exec -it -n flowise deployment/flowise -- nc -zv postgres 5432
```

**Common issues:**
- PostgreSQL not ready (check readiness probe)
- Wrong credentials in ConfigMap
- PVC not bound

**Reset Flowise:**
```bash
kubectl delete deployment flowise postgres -n flowise
kubectl delete pvc postgres-pvc flowise-pvc -n flowise
kubectl apply -f mk-flowise.yml
```

### Flink Operator Issues

**Check operator logs:**
```bash
kubectl logs -n flink deployment/flink-kubernetes-operator
```

**Verify CRD installation:**
```bash
kubectl get crd | grep flink
```

**Common issues:**
- FlinkDeployment CRD not installed
- Insufficient RBAC permissions
- Invalid FlinkDeployment spec

**Reinstall operator:**
```bash
helm uninstall flink-kubernetes-operator -n flink
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator -n flink
```

### Trino Pods Not Starting

**Check init container logs:**
```bash
kubectl logs <pod-name> -c generate-keystore -n trino
```

**Check main container logs:**
```bash
kubectl logs <pod-name> -c trino -n trino
```

**Common issues:**
- Insufficient resources (increase Minikube memory/CPU)
- ConfigMap not mounted correctly
- Network connectivity issues

### MinIO Pods Not Ready

**Check PVC status:**
```bash
kubectl get pvc -n minio
kubectl describe pvc <pvc-name> -n minio
```

**Check MinIO logs:**
```bash
kubectl logs minio-0 -n minio
```

**Common issues:**
- Storage provisioner not available
- Insufficient disk space
- Network communication between pods

### Hive Metastore Connection Issues

**Test PostgreSQL connectivity:**
```bash
kubectl exec -n trino deployment/hive-metastore -- \
  nc -zv postgres 5432
```

**Check PostgreSQL status:**
```bash
kubectl exec -it postgres-0 -n trino -- psql -U hive -d metastore -c "\dt"
```

**Verify init containers completed:**
```bash
kubectl describe pod <hive-metastore-pod> -n trino
```

### Cannot Access Services Locally

**Verify port-forward is active:**
```bash
# Check running port-forwards
ps aux | grep "port-forward"

# Kill and restart if needed
kubectl port-forward -n trino svc/trino 8443:8443
```

**Check NodePort services:**
```bash
kubectl get svc -n trino
minikube service list
```

## Resource Management

### Scale Workers

```bash
# Scale up to 3 workers
kubectl scale deployment trino-worker -n trino --replicas=3

# Scale down to 1 worker
kubectl scale deployment trino-worker -n trino --replicas=1
```

### Restart Components

```bash
# Restart coordinator
kubectl rollout restart deployment/trino-coordinator -n trino

# Restart workers
kubectl rollout restart deployment/trino-worker -n trino

# Restart all Trino components
kubectl delete deployment trino-coordinator trino-worker -n trino
kubectl apply -f mk-trino-https-auth.yml
```

### Resource Limits

Adjust resource limits in YAML files based on your system:

```yaml
resources:
  requests:
    memory: "2Gi"    # Minimum required
    cpu: "1000m"     # 1 CPU core
  limits:
    memory: "4Gi"    # Maximum allowed
    cpu: "2000m"     # 2 CPU cores
```

## Cleanup

### Delete Deployments (Keep Minikube)

```bash
# Delete Kafka
kubectl delete -f mk-kafka-ha.yml
kubectl delete namespace kafka

# Delete Flowise
kubectl delete -f mk-flowise.yml
kubectl delete namespace flowise

# Delete Flink Operator
helm uninstall flink-kubernetes-operator -n flink
kubectl delete namespace flink

# Delete Trino components
kubectl delete -f mk-trino-https-auth.yml

# Delete MinIO
kubectl delete -f mk-minio-ha-r2.yml

# Delete namespaces (and all resources)
kubectl delete namespace trino
kubectl delete namespace minio
```

### Stop Minikube

```bash
# Stop cluster (preserves state)
minikube stop

# Delete cluster (removes all data)
minikube delete
```

### Reset Everything

```bash
# Delete all and start fresh
minikube delete
minikube start --cpus=4 --memory=8192 --disk-size=40g
```

## Performance Tuning

### Minikube Configuration

```bash
# Increase resources
minikube config set cpus 6
minikube config set memory 12288
minikube config set disk-size 60g

# Apply changes (requires restart)
minikube delete
minikube start
```

### Trino Memory Settings

Edit ConfigMaps to adjust Trino memory:

```yaml
# In trino-coordinator ConfigMap
query.max-memory=4GB          # Total query memory
query.max-memory-per-node=2GB # Per-node memory

# In JVM config
-Xmx4G  # Heap size
```

### MinIO Performance

For better I/O performance, use Minikube with:
```bash
# Use native Docker driver (best performance)
minikube start --driver=docker --cpus=4 --memory=8192
```

## Development Workflow

### Quick Iteration

```bash
# Apply changes without downtime
kubectl apply -f mk-trino-https-auth.yml

# Force restart
kubectl rollout restart deployment/trino-coordinator -n trino

# Watch pod startup
kubectl get pods -n trino -w
```

### Testing Queries

Use the Python client for automated testing:

```python
# test_queries.py
import urllib3
from trino.dbapi import connect
from trino.auth import BasicAuthentication

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def run_test():
    conn = connect(
        host='localhost',
        port=8443,
        user='admin',
        http_scheme='https',
        auth=BasicAuthentication('admin', 'admin123'),
        verify=False
    )
    
    cur = conn.cursor()
    
    # Test catalog access
    cur.execute('SHOW CATALOGS')
    catalogs = cur.fetchall()
    assert len(catalogs) > 0, "No catalogs found"
    
    print("✓ All tests passed")
    
    cur.close()
    conn.close()

if __name__ == '__main__':
    run_test()
```

## Differences from Production (AWS/GCP)

| Feature | Minikube | AWS/GCP |
|---------|----------|---------|
| Load Balancer | NodePort + port-forward | ELB / GCP LB |
| Storage | Local PV / emptyDir | EBS / Persistent Disk |
| Certificates | Self-signed | ACM / Valid CA |
| Autoscaling | Manual | HPA + Cluster Autoscaler |
| Monitoring | kubectl logs | CloudWatch / Cloud Logging |
| HA | Single node | Multi-AZ |
| Backup | Manual | Automated snapshots |
| Network | Single node | VPC + Private subnets |

## Table Format Comparison

### Apache Hive
- **Type**: Traditional data warehouse
- **Formats**: Parquet, ORC, Avro
- **ACID**: Limited support
- **Use case**: Legacy systems

### Apache Iceberg
- **Type**: Modern table format
- **ACID**: Full serializable isolation
- **Features**: Time travel, schema evolution, partition evolution
- **Use case**: New projects requiring multi-engine support

### Delta Lake
- **Type**: Databricks table format
- **ACID**: Full transactional support
- **Features**: Time travel, MERGE/UPDATE/DELETE operations
- **Use case**: Spark/Databricks-centric workflows

### Lance
- **Type**: Vector-optimized format
- **Features**: Efficient vector storage, ML-optimized
- **Use case**: Vector embeddings, ML workloads

## Additional Resources

### Quick Reference - Service Access

| Service | Port-Forward Command | URL | Credentials |
|---------|---------------------|-----|-------------|
| Trino HTTPS | `kubectl port-forward -n trino svc/trino 8443:8443` | https://localhost:8443 | admin / admin123 |
| Trino HTTP | `kubectl port-forward -n trino svc/trino 8080:8080` | http://localhost:8080 | - |
| MinIO Console | `kubectl port-forward -n minio svc/minio-console 9001:9001` | http://localhost:9001 | admin / password123 |
| Kafka UI | `kubectl port-forward -n kafka svc/kafka-ui 8080:8080` | http://localhost:8080 | - |
| Flowise | `kubectl port-forward -n flowise svc/flowise 3000:3000` | http://localhost:3000 | admin / admin123 |

### Quick Reference - Internal Service Endpoints

| Service | Internal Endpoint | Port | Use Case |
|---------|------------------|------|----------|
| Kafka Bootstrap | `kafka-0.kafka-headless.kafka.svc.cluster.local` | 9092 | Producer/Consumer |
| Kafka Broker 1 | `kafka-1.kafka-headless.kafka.svc.cluster.local` | 9092 | Producer/Consumer |
| Flowise API | `flowise.flowise.svc.cluster.local` | 3000 | Internal API calls |
| Flowise DB | `postgres.flowise.svc.cluster.local` | 5432 | Database connection |
| Trino | `trino.trino.svc.cluster.local` | 8080 | Internal queries |
| MinIO API | `minio.minio.svc.cluster.local` | 9000 | S3 operations |
| Hive Metastore | `hive-metastore.trino.svc.cluster.local` | 9083 | Metadata queries |

### Configuration Files Reference

| Component | Config File | Description |
|-----------|-------------|-------------|
| Kafka | [mk-kafka-ha.yml](mk-kafka-ha.yml) | 2-node KRaft cluster with UI |
| Flowise | [mk-flowise.yml](mk-flowise.yml) | AI workflow builder with PostgreSQL |
| Trino | [mk-trino-https-auth.yml](mk-trino-https-auth.yml) | Query engine with HTTPS auth |
| MinIO | [mk-minio-ha-r2.yml](mk-minio-ha-r2.yml) | 4-node distributed storage |

### Documentation
- **Trino**: https://trino.io/docs/current/
- **MinIO**: https://min.io/docs/minio/kubernetes/upstream/
- **Apache Iceberg**: https://iceberg.apache.org/
- **Apache Kafka**: https://kafka.apache.org/documentation/
- **Apache Flink**: https://nightlies.apache.org/flink/flink-docs-stable/
- **Flink Kubernetes Operator**: https://nightlies.apache.org/flink/flink-kubernetes-operator-docs-stable/
- **Flowise**: https://docs.flowiseai.com/
- **Minikube**: https://minikube.sigs.k8s.io/docs/

### Community
- Trino Slack: https://trino.io/slack.html
- MinIO Slack: https://slack.min.io/
- Apache Kafka Users: https://kafka.apache.org/contact
- Flink User Mailing List: https://flink.apache.org/community.html
- Flowise Discord: https://discord.gg/jbaHfsRVBW

### Notes Files
- See [mk-notes.md](mk-notes.md) for detailed operational commands and examples

## License

See [LICENSE](../LICENCE) file in the root directory.
