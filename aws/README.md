# AIchemy AWS Architecture

This directory contains the infrastructure and deployment configurations for running the AIchemy data lakehouse platform on AWS EKS (Elastic Kubernetes Service).

## Architecture Overview

The AIchemy platform provides a complete data lakehouse solution with support for multiple table formats (Hive, Iceberg, Delta Lake, Lance) running on Kubernetes with Trino as the query engine and MinIO as S3-compatible storage.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud - VPC                                     │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                     EKS Cluster (Private Subnets)                           │ │
│  │                                                                             │ │
│  │  ┌────────────────────────────────┐  ┌────────────────────────────────────┐ │ │
│  │  │    Kafka Namespace (Streaming) │  │  Flink Namespace (Processing)      │ │ │
│  │  │                                │  │                                    │ │ │
│  │  │  ┌──────────┐  ┌──────────┐    │  │  ┌─────────────────────────────┐   │ │ │
│  │  │  │ Kafka-0  │  │ Kafka-1  │    │  │  │  Flink Kubernetes Operator  │   │ │ │
│  │  │  │ (Broker) │  │ (Broker) │    │  │  │  • CRD Management           │   │ │ │
│  │  │  │          │  │          │    │  │  └─────────────────────────────┘   │ │ │
│  │  │  │ KRaft    │  │ KRaft    │    │  │                                    │ │ │
│  │  │  │ Mode     │  │ Mode     │    │  │  ┌─────────────┐  ┌─────────────┐  │ │ │
│  │  │  │:9092 :94 │  │:9092 :94 │    │  │  │  JobMgr     │  │TaskManagers │  │ │ │
│  │  │  │    4     │  │    4     │    │  │  │  (Session)  │  │  (Parallel) │  │ │ │
│  │  │  └────┬─────┘  └────┬─────┘    │  │  │ :8081       │  │ :8081       │  │ │ │
│  │  │       │             │          │  │  └─────────────┘  └─────────────┘  │ │ │
│  │  │  ┌────▼─────────────▼──────┐   │  │        │              │            │ │ │
│  │  │  │   Kafka UI              │   │  │        └──────┬───────┘            │ │ │
│  │  │  │  :8080                  │   │  │               │                    │ │ │
│  │  │  └─────────────────────────┘   │  │               ▼                    │ │ │
│  │  └────────────────────────────────┘  │         Kafka Topics               │ │ │
│  │                                      └────────────────────────────────────┘ │ │
│  │                                                                             │ │
│  │  ┌─────────────────────────────────┐  ┌───────────────────────────────────┐ │ │
│  │  │ Flowise Namespace (AI Flows)    │  │    Trino Namespace (Query Engine) │ │ │
│  │  │                                 │  │                                   │ │ │
│  │  │  ┌────────────────────────────┐ │  │  ┌─────────────┐  ┌─────────────┐ │ │ │
│  │  │  │  Flowise Server            │ │  │  │Trino Coord. │  │ Trino       │ │ │ │
│  │  │  │  • Node.js                 │ │  │  │ (1 replica) │  │ Worker      │ │ │ │
│  │  │  │  • LangChain Integration   │ │  │  │             │  │ (2 replicas)│ │ │ │
│  │  │  │  • Vector Store Support    │ │  │  │ :8080 :8443 │  │ :8080 :8443 │ │ │ │
│  │  │  │  :3000                     │ │  │  │             │  │             │ │ │ │
│  │  │  └────────────┬───────────────┘ │  │  └──────┬──────┘  └──────┬──────┘ │ │ │
│  │  │               │                 │  │         │                │        │ │ │
│  │  │  ┌────────────▼──────────────┐  │  │         │                │        │ │ │
│  │  │  │ PostgreSQL (Flowise)      │  │  │         ├────────┬───────┘        │ │ │
│  │  │  │ • Workflow Storage        │  │  │         │        │                │ │ │
│  │  │  │ • Vector Index            │  │  │         ▼        ▼                │ │ │
│  │  │  │ :5432                     │  │  │   Hive Metastore   PostgreSQL     │ │ │
│  │  │  │ • Storage: EBS (gp3)      │  │  │    (Metadata)       (Metadata)    │ │ │
│  │  │  └───────────────────────────┘  │  │     :9083            :5432        │ │ │
│  │  └─────────────────────────────────┘  └───────────────────────────────────┘ │ │
│  │                                                                             │ │
│  │  ┌────────────────────────────────────────────────────────────────────────┐ │ │
│  │  │           MinIO Namespace (Object Storage & Data Lake)                 │ │ │
│  │  │                                                                        │ │ │
│  │  │  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐                                │ │ │
│  │  │  │MinIO │  │MinIO │  │MinIO │  │MinIO │                                │ │ │
│  │  │  │Pod-0 │  │Pod-1 │  │Pod-2 │  │Pod-3 │                                │ │ │
│  │  │  │:9000 │  │:9000 │  │:9000 │  │:9000 │                                │ │ │
│  │  │  │:9001 │  │:9001 │  │:9001 │  │:9001 │                                │ │ │
│  │  │  └───┬──┘  └───┬──┘  └───┬──┘  └───┬──┘                                │ │ │
│  │  │      │         │         │         │                                   │ │ │
│  │  │      └─────────┴─────────┴─────────┘                                   │ │ │
│  │  │                  │                                                     │ │ │
│  │  │          ┌───────▼────────┐                                            │ │ │
│  │  │          │ EBS Volumes    │                                            │ │ │
│  │  │          │ (4x 20Gi gp3)  │                                            │ │ │
│  │  │          └────────────────┘                                            │ │ │
│  │  └────────────────────────────────────────────────────────────────────────┘ │ │
│  │                                                                             │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐ │
│  │                        External Access (NLB/ALB)                            │ │
│  │                                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │ Kafka NLB    │  │ Trino ALB    │  │ Flowise ALB  │  │ MinIO Console│     │ │
│  │  │ :9094        │  │ :8443 :8080  │  │ :3000        │  │ :9001 :9000  │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Kafka Streaming

**Purpose**: Distributed message broker for real-time data streaming

**Architecture**:
- **KRaft Mode**: No Zookeeper dependency, controller nodes embedded
- **2-node HA**: Replication factor 2, partition count 3
- **Storage**: EBS gp3 volumes (20Gi per node)
- **External Access**: Network Load Balancers for per-broker access

**Features**:
- Automatic broker discovery via StatefulSet
- Kafka UI for cluster monitoring and management
- External bootstrap servers via LoadBalancer
- 7-day message retention by default
- Cross-zone load balancing

**Endpoints**:
- Internal: `kafka-0.kafka-headless.kafka.svc.cluster.local:9092`
- External: `<kafka-0-nlb>.<region>.elb.amazonaws.com:9094`
- Kafka UI: `<kafka-ui-nlb>.<region>.elb.amazonaws.com:8080`

### 2. Flink Kubernetes Operator

**Purpose**: Stream processing with Flink job orchestration

**Architecture**:
- **Kubernetes Operator**: Manages Flink deployments via CRDs
- **Session Cluster**: JobManager + TaskManagers for parallelization
- **Job Submission**: Deploy Flink jobs via FlinkDeployment resources
- **External Monitoring**: Flink Web UI on JobManager (:8081)

**Features**:
- CRD-based deployment management
- Automatic scaling based on parallelism
- Savepoint support for fault tolerance
- Integration with Kafka for streaming ingestion
- Job restart policies and recovery

**Key Resources**:
- Flink Operator Deployment (operator namespace)
- JobManager (1 replica, high availability)
- TaskManagers (3 replicas, configurable parallelism)
- ConfigMaps for job configurations

### 3. Flowise AI Workflows

**Purpose**: Low-code platform for building AI workflows and LLM applications

**Architecture**:
- **Node.js Server**: Runtime for workflow execution
- **PostgreSQL Backend**: Persistent workflow storage
- **LangChain Integration**: Support for multiple LLM providers
- **Vector Store Support**: Integration with Lance, Pinecone, and others
- **REST API**: Expose workflows as APIs

**Features**:
- Drag-and-drop workflow builder UI
- Support for RAG (Retrieval Augmented Generation)
- Custom tool creation and execution
- Workflow versioning and deployment
- Integration with Trino for data queries
- Integration with MinIO for document storage

**Endpoints**:
- UI: `<flowise-alb>.<region>.elb.amazonaws.com:3000`
- API: `<flowise-alb>.<region>.elb.amazonaws.com:3000/api/v1/prediction/<CHATFLOW_ID>`

**Database**:
- PostgreSQL 15 for workflow persistence
- Persistent volume for vector embeddings

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
- Request: 4Gi RAM, 2 CPU per pod
- Limit: 8Gi RAM, 4 CPU per pod

### 5. MinIO Object Storage (HA)

**Purpose**: S3-compatible object storage for data lake files

**Architecture**:
- 4-node distributed deployment with erasure coding
- Tolerates up to 2 node failures
- StatefulSet with persistent storage

**Storage**:
- 4 EBS volumes (gp3 storage class)
- 20Gi per volume (80Gi total)

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
- PostgreSQL JDBC driver (auto-downloaded)
- Hadoop AWS + AWS SDK bundles (auto-downloaded)

### 7. PostgreSQL Database

**Purpose**: Persistent metadata storage for Hive Metastore and Flowise

**Configuration**:
- Database: `metastore` (Hive), `flowise` (Flowise)
- User: `hive` (Hive), `flowise` (Flowise)
- Password: `hivepassword` (Hive), `flowisepassword` (Flowise)

**Storage**:
- 20Gi EBS volume (gp3 storage class)
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

### Step 3: Deploy Kafka (Optional - for streaming)

```bash
# Deploy Kafka HA cluster
kubectl apply -f aws-kafka-ha.yml

# Wait for Kafka brokers to be ready
kubectl wait --for=condition=ready pod -l app=kafka -n kafka --timeout=300s

# Verify deployment
kubectl get pods -n kafka
kubectl get pvc -n kafka
kubectl get svc -n kafka
```

**Get LoadBalancer addresses for external access:**
```bash
# Get Kafka UI LoadBalancer address
kubectl get svc kafka-ui -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get individual broker LoadBalancer addresses
kubectl get svc kafka-0-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc kafka-1-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Update external hosts ConfigMap:**
```bash
# Save the LoadBalancer hostnames
KAFKA_0_LB=$(kubectl get svc kafka-0-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
KAFKA_1_LB=$(kubectl get svc kafka-1-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update ConfigMap
kubectl patch configmap kafka-external-hosts -n kafka --type merge -p "{\"data\":{\"kafka-0\":\"$KAFKA_0_LB\",\"kafka-1\":\"$KAFKA_1_LB\"}}"

# Restart Kafka pods to pick up new configuration
kubectl rollout restart statefulset kafka -n kafka
```

**Access Kafka UI:**
```bash
KAFKA_UI_LB=$(kubectl get svc kafka-ui -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Kafka UI: http://$KAFKA_UI_LB:8080"
```

### Step 4: Deploy Flink Kubernetes Operator (Optional - for stream processing)

```bash
# Add Flink Helm repository
helm repo add flink-operator-repo https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.8.0/
helm repo update

# Create namespace and install operator
kubectl create namespace flink-operator-system
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
  --namespace flink-operator-system \
  --set image.repository=apache/flink-kubernetes-operator \
  --set image.tag=1.8.0

# Wait for operator to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=flink-kubernetes-operator \
  -n flink-operator-system --timeout=300s

# Verify operator installation
kubectl get pods -n flink-operator-system
kubectl get crds | grep flink
```

# Deploy a Basic Example
kubectl create -f https://raw.githubusercontent.com/apache/flink-kubernetes-operator/release-1.13/examples/basic.yaml


### Step 5: Deploy Flowise (Optional - for AI workflows)

```bash
# Deploy Flowise with PostgreSQL backend
kubectl apply -f aws-flowise.yml

# Wait for Flowise and database to be ready
kubectl wait --for=condition=ready pod -l app=flowise -n flowise --timeout=300s
kubectl wait --for=condition=ready pod -l app=flowise-db -n flowise --timeout=300s

# Verify deployment
kubectl get pods -n flowise
kubectl get pvc -n flowise
kubectl get svc -n flowise
```

**Get LoadBalancer address:**
```bash
kubectl get svc flowise -n flowise -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

**Access Flowise UI:**
```bash
FLOWISE_LB=$(kubectl get svc flowise -n flowise -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Flowise UI: http://$FLOWISE_LB:3000"
```

### Step 6: Deploy MinIO
```bash
kubectl apply -f aws-minio-ha.yml
```

Verify MinIO deployment:
```bash
kubectl get pods -n minio
kubectl get pvc -n minio
```

### Step 7: Deploy Trino with HTTPS & Auth
```bash
kubectl apply -f aws-trino-https-auth.yml
```

Verify Trino deployment:
```bash
kubectl get pods -n trino
kubectl get svc -n trino
```

### Step 8: Get Load Balancer Endpoint
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

### Flowise Workflows

#### Access Flowise UI
```bash
# Get LoadBalancer external hostname
kubectl -n flowise get svc flowise -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Open browser: http://<FLOWISE-EXTERNAL-LB>:3000
```

#### Example Workflow: RAG with Vector Store
1. **Create a Chatflow:**
   - Open Flowise UI at `http://<FLOWISE-EXTERNAL-LB>:3000`
   - Click "Add New Chatflow"
   - Add nodes:
     - Document Loader → PDF File
     - Text Splitter → Recursive Character Text Splitter
     - Embeddings → OpenAI Embeddings
     - Vector Store → Lance
     - Retriever → Lance Retriever
     - LLM → ChatOpenAI
     - Chain → Conversational Retrieval QA Chain

2. **Test the Workflow:**
   - Upload a PDF document
   - Ask questions in the chat interface
   - The system will retrieve relevant context from Lance vector store

#### Flowise API Usage
```python
import requests
import json

# Flowise API endpoint
FLOWISE_URL = "http://<FLOWISE-EXTERNAL-LB>:3000/api/v1/prediction/<CHATFLOW_ID>"

# Send query
response = requests.post(
    FLOWISE_URL,
    json={
        "question": "What is the main topic of the document?",
        "overrideConfig": {
            "temperature": 0.7
        }
    }
)

result = response.json()
print(f"Answer: {result['text']}")
```

#### Connect Flowise to Trino (for data queries)
1. In Flowise UI, add a "Custom Tool" node
2. Configure it to query Trino via HTTP:
```javascript
const { Client } = require('trino-client');

const client = new Client({
    server: 'http://trino-coordinator.trino.svc.cluster.local:8080',
    catalog: 'iceberg',
    schema: 'ic_test'
});

async function queryTrino(sql) {
    const result = await client.query(sql);
    return result;
}

// Use in tool function
const answer = await queryTrino("SELECT COUNT(*) FROM orders");
```

### Flink Stream Processing

#### Deploy Sample Flink Job
```bash
# Create Flink session cluster configuration
cat > flink-session.yml <<EOF
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: flink-session
  namespace: flink
spec:
  image: flink:1.17-scala_2.12
  flinkVersion: v1_17
  taskManager:
    replicas: 3
    resource:
      memory: "2048m"
      cpu: 1
  jobManager:
    replicas: 2
    resource:
      memory: "2048m"
      cpu: 1
  job:
    jarURI: s3://flink-jobs/kafka-flink-job.jar
    entryClass: com.example.KafkaFlinkJob
    args:
      - --kafka-broker=kafka-0.kafka-headless.kafka.svc.cluster.local:9092
      - --kafka-topic=flink-input
      - --output-topic=flink-output
    parallelism: 3
    upgradeMode: stateless
  serviceAccount: flink
EOF

kubectl apply -f flink-session.yml
```

#### Monitor Flink Job
```bash
# Port forward to Flink UI
kubectl port-forward -n flink svc/flink-session-rest 8081:8081

# Open browser: http://localhost:8081
```

#### Kafka to Flink to Kafka Pipeline
```python
# Python Kafka producer that sends data to Flink
from kafka import KafkaProducer
import json
import time

KAFKA_BROKERS = ['<kafka-0-lb>:9094', '<kafka-1-lb>:9094']

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKERS,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Produce sample data
for i in range(1000):
    event = {
        'id': i,
        'timestamp': time.time(),
        'value': i * 2,
        'source': 'aws-producer'
    }
    producer.send('flink-input', value=event)
    time.sleep(1)

producer.close()
```

#### Verify Flink Job Output
```bash
# Consume messages from output topic
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --topic flink-output \
  --from-beginning \
  --max-messages 10
```

### Kafka Producer/Consumer Examples

#### Python Producer (External Access)
```python
from kafka import KafkaProducer
import json

# Get LoadBalancer addresses
# KAFKA_0_LB = <from kubectl get svc kafka-0-external>
# KAFKA_1_LB = <from kubectl get svc kafka-1-external>

producer = KafkaProducer(
    bootstrap_servers=[
        '<kafka-0-lb>.elb.us-east-1.amazonaws.com:9094',
        '<kafka-1-lb>.elb.us-east-1.amazonaws.com:9094'
    ],
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Send messages
for i in range(10):
    message = {'id': i, 'value': f'message-{i}', 'source': 'aws-eks'}
    producer.send('test-topic', message)
    print(f"Sent: {message}")

producer.flush()
producer.close()
```

#### Python Consumer (External Access)
```python
from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    'test-topic',
    bootstrap_servers=[
        '<kafka-0-lb>.elb.us-east-1.amazonaws.com:9094',
        '<kafka-1-lb>.elb.us-east-1.amazonaws.com:9094'
    ],
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
    auto_offset_reset='earliest',
    group_id='aws-consumer-group'
)

print("Waiting for messages from AWS Kafka...")
for message in consumer:
    print(f"Received: {message.value}")
```

#### Using kubectl exec (Inside cluster)
```bash
# Create topic with replication
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --create --topic aws-events --partitions 3 --replication-factor 2 \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# List topics
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# Describe topic
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-topics.sh \
  --describe --topic aws-events \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# Produce messages
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-producer.sh \
  --topic aws-events --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092

# Consume messages
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --topic aws-events --from-beginning \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092
```

#### Check cluster health
```bash
# Check cluster metadata
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-metadata.sh \
  --snapshot /var/lib/kafka/data/logs/__cluster_metadata-0/00000000000000000000.log \
  --print

# Check consumer groups
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092 --list

# Describe consumer group
kubectl exec -it kafka-0 -n kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --describe --group aws-consumer-group
```

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

### Flink Operator Issues

```bash
# Check operator status
kubectl get pods -n flink-operator-system
kubectl logs -n flink-operator-system deployment/flink-kubernetes-operator

# Verify CRD installation
kubectl get crds | grep flink

# Check Flink deployment status
kubectl get flinkdeployment -A
kubectl describe flinkdeployment <deployment-name> -n <namespace>

# Operator webhook issues
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# Delete and reinstall if webhook conflicts
kubectl delete validatingwebhookconfiguration flink-operator-webhook-configuration
helm uninstall flink-kubernetes-operator -n flink-operator-system
helm repo add flink-operator-repo https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.8.0/
helm install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator -n flink-operator-system
```

### Flowise Connection Issues

```bash
# Check Flowise pods
kubectl get pods -n flowise
kubectl describe pod <flowise-pod> -n flowise

# Check logs
kubectl logs -n flowise deployment/flowise
kubectl logs -n flowise statefulset/flowise-db

# Verify database connectivity
kubectl -n flowise exec -it statefulset/flowise-db -- psql -U flowise -d flowise -c '\l'

# Check LoadBalancer provisioning
kubectl get svc -n flowise
kubectl describe svc flowise -n flowise

# Test connectivity from bastion
curl http://<FLOWISE-EXTERNAL-LB>:3000/api/v1/health

# Database initialization issues
kubectl -n flowise exec -it statefulset/flowise-db -- psql -U flowise -d flowise -c '\dt'

# Restart Flowise if needed
kubectl rollout restart deployment/flowise -n flowise
```

### LoadBalancer Provisioning Delays

```bash
# AWS Load Balancers can take 2-5 minutes to provision
# Check service status
kubectl get svc -A | grep LoadBalancer

# Describe specific service
kubectl describe svc <service-name> -n <namespace>

# Check AWS EC2 console for load balancer status
aws elbv2 describe-load-balancers --region <region>

# Force recreation if stuck
kubectl delete svc <service-name> -n <namespace>
kubectl apply -f <manifest-file>
```

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
- **Storage formatting failed**: Check PVC and storage class
  ```bash
  kubectl get pvc -n kafka
  kubectl describe pvc datadir-kafka-0 -n kafka
  ```
- **Network communication**: Verify headless service
  ```bash
  kubectl get svc kafka-headless -n kafka
  kubectl describe svc kafka-headless -n kafka
  ```
- **Cluster ID mismatch**: Delete PVCs and restart
  ```bash
  kubectl delete statefulset kafka -n kafka
  kubectl delete pvc -l app=kafka -n kafka
  kubectl apply -f aws-kafka-ha.yml
  ```

**Verify EBS CSI driver:**
```bash
kubectl get pods -n kube-system | grep ebs-csi
# If not present, run aws-fix-ebs-csi.sh
```

### LoadBalancer Not Getting External IP

**Check service status:**
```bash
kubectl get svc -n kafka
kubectl describe svc kafka-0-external -n kafka
```

**Common issues:**
- **IAM permissions**: Ensure EKS node role has permissions for ELB
- **Subnet tags**: Private subnets must have `kubernetes.io/role/internal-elb=1`
- **Security groups**: Verify inbound rules allow port 9094

**Check AWS Load Balancer Controller:**
```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Kafka External Access Not Working

**Verify LoadBalancer addresses are configured:**
```bash
kubectl get configmap kafka-external-hosts -n kafka -o yaml
```

**Test connectivity from external client:**
```bash
# Get LoadBalancer hostname
LB_HOST=$(kubectl get svc kafka-0-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test TCP connection
nc -zv $LB_HOST 9094
telnet $LB_HOST 9094
```

**Update ConfigMap if missing:**
```bash
KAFKA_0_LB=$(kubectl get svc kafka-0-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
KAFKA_1_LB=$(kubectl get svc kafka-1-external -n kafka -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

kubectl patch configmap kafka-external-hosts -n kafka --type merge \
  -p "{\"data\":{\"kafka-0\":\"$KAFKA_0_LB\",\"kafka-1\":\"$KAFKA_1_LB\"}}"

kubectl rollout restart statefulset kafka -n kafka
```

### Kafka UI Cannot Connect to Brokers

**Check Kafka UI logs:**
```bash
kubectl logs -n kafka deployment/kafka-ui
```

**Verify internal connectivity:**
```bash
kubectl exec -n kafka deployment/kafka-ui -- \
  nc -zv kafka-0.kafka-headless.kafka.svc.cluster.local 9092
```

**Restart Kafka UI:**
```bash
kubectl rollout restart deployment/kafka-ui -n kafka
```

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
