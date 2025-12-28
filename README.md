## AIchemy

**Bigdata and AI Platform**

## Overview

AIchemy is a comprehensive data lakehouse platform designed for big data analytics and AI workloads. It provides a unified architecture for querying multiple table formats (Hive, Iceberg, Delta Lake, Lance) with support for both traditional analytics and modern machine learning use cases including vector embeddings.

The platform is cloud-native, Kubernetes-based, and can be deployed on multiple environments:
- **Minikube**: Local development and testing
- **AWS EKS**: Production deployment on Amazon Web Services
- **GCP GKE**: Production deployment on Google Cloud Platform

## High-Level Architecture

### System Components

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                                Client Layer                                    │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐                    │
│  │  Python Client │  │   Trino CLI    │  │   Web Apps     │                    │
│  └────────────────┘  └────────────────┘  └────────────────┘                    │
└────────────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                        OPTIONAL: Real-Time Pipeline Layer                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │              Kafka Message Broker (Streaming Events)                    │   │
│  │              Topic-based pub/sub for event ingestion                    │   │
│  │              ├─ KRaft mode (no Zookeeper)                               │   │
│  │              └─ HA with multiple brokers                                │   │
│  └────────────────────────┬────────────────────────────────────────────────┘   │
│                           │                                                    │
│                           ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │              Flink Stream Processing (Kubernetes Operator)              │   │
│  │              Real-time transformations and aggregations                 │   │
│  │              ├─ JobManager + TaskManagers                               │   │
│  │              ├─ Kafka source/sink integration                           │   │
│  │              └─ Result to Iceberg/Lance tables                          │   │
│  └────────────────────────┬────────────────────────────────────────────────┘   │
│                           │                                                    │
└───────────────────────────┼────────────────────────────────────────────────────┘
                            │
┌──────────────────────────────────────────────────────────────────────────────────┐
│                      Query Engine Layer (Core)                                   │
│  ┌──────────────────────────────────────────────────────────────────────────┐    │
│  │                      Trino Cluster (SQL Query)                           │    │
│  │                                                                          │    │
│  │  ┌──────────────┐       ┌──────────────┐  ┌──────────────┐               │    │
│  │  │ Coordinator  │────►  │   Worker 1   │  │   Worker 2   │               │    │
│  │  │              │       │              │  │              │               │    │
│  │  │ • Planning   │       │ • Execution  │  │ • Execution  │               │    │
│  │  │ • Scheduling │       │ • Processing │  │ • Processing │               │    │
│  │  │ • Aggregation│       │              │  │              │               │    │
│  │  └──────────────┘       └──────────────┘  └──────────────┘               │    │
│  └──────────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
         ┌──────────────────┐  ┌──────────────────────────────┐
         │   Thrift Protocol│  │  OPTIONAL: Flowise AI        │
         │                  │  │  Workflow Builder            │
         │                  │  │  ├─ LangChain Integration    │
         │                  │  │  ├─ Vector Store Support     │
         │                  │  │  └─ REST API for Workflows   │
         └────────┬─────────┘  └──────────────────────────────┘
                  │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        Metadata Layer                                           │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                 Hive Metastore (Catalog Service)                           │ │
│  │                                                                            │ │
│  │  • Table Schemas       • Column Statistics                                 │ │
│  │  • Partition Info      • Storage Locations                                 │ │
│  └────────────────────────────┬───────────────────────────────────────────────┘ │
│                               │                                                 │
│                               │ JDBC                                            │
│                               ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                      PostgreSQL Database                                   │ │
│  │  (Persistent metadata storage for Hive + OPTIONAL Flowise workflows)       │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ S3 API
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         Storage Layer                                           │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                   MinIO Object Storage (HA)                                │ │
│  │                                                                            │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                        │ │
│  │  │ Node 0  │  │ Node 1  │  │ Node 2  │  │ Node 3  │                        │ │
│  │  │         │  │         │  │         │  │         │                        │ │
│  │  │ Bucket  │  │ Bucket  │  │ Bucket  │  │ Bucket  │                        │ │
│  │  │ Shards  │  │ Shards  │  │ Shards  │  │ Shards  │                        │ │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘                        │ │
│  │                                                                            │ │
│  │  Erasure Coding: Tolerates up to 2 node failures                           │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                   │                                             │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                     Data Lake Storage                                      │ │
│  │                                                                            │ │
│  │  ├─ /warehouse        (Hive tables)                                        │ │
│  │  ├─ /iceberg-bucket   (Iceberg tables)                                     │ │
│  │  ├─ /delta-bucket     (Delta Lake tables)                                  │ │
│  │  └─ /lance-bucket     (Lance vector embeddings)                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Core Components

#### 1. Trino Query Engine
**Distributed SQL query engine for interactive analytics**

- **Coordinator**: Single instance that receives queries, plans execution, and aggregates results
- **Workers**: Multiple instances that execute query tasks in parallel
- **Features**:
  - Massively parallel processing (MPP)
  - Support for multiple data sources via connectors
  - Advanced query optimization
  - ANSI SQL compliance
  - Federation across multiple catalogs

**Communication**:
- External clients → HTTPS (port 8443) with password authentication
- Internal cluster → HTTP (port 8080) with shared secret authentication

#### 2. Hive Metastore
**Centralized metadata catalog and schema registry**

- Stores and manages metadata for all table formats
- Provides schema evolution and versioning
- Maintains partition information and statistics
- Supports multiple clients simultaneously via Thrift protocol

**Managed Metadata**:
- Table definitions and schemas
- Column types and constraints
- Partition specifications
- Storage locations (S3/MinIO paths)
- Table properties and statistics

#### 3. PostgreSQL Database
**Persistent metadata storage backend**

- Stores Hive Metastore metadata persistently
- Enables atomic operations on metadata
- Provides ACID guarantees for catalog operations
- Supports concurrent access from Metastore instances

#### 4. MinIO Object Storage
**S3-compatible distributed object storage**

- High-availability (HA) deployment with 4 nodes
- Erasure coding for data protection (tolerates 2 node failures)
- S3 API compatibility for seamless integration
- Suitable for both hot and cold data storage

**Storage Organization**:
- Separate buckets per table format
- Optimized for read-heavy analytics workloads
- Versioning support for data lineage
- Lifecycle policies for data management

### Optional Components

#### 1. Apache Kafka
**Distributed message broker for real-time streaming**

- Event-driven data ingestion pipeline
- KRaft mode deployment (no Zookeeper dependency)
- High availability with multiple brokers (2+ replicas)
- Topic-based pub/sub for decoupled systems
- Integration with Flink for stream processing
- External access via Network Load Balancers

**Key Features**:
- Configurable retention policies (default: 7 days)
- Partition-based parallel consumption
- Exactly-once semantics support
- Consumer group management
- Kafka UI for monitoring and topic management

**Use Cases**:
- Real-time data ingestion
- Event streaming from applications
- Change data capture (CDC) pipelines
- IoT sensor data collection

#### 2. Apache Flink (Kubernetes Operator)
**Stream processing engine for real-time transformations**

- CRD-based deployment management via Kubernetes Operator
- Session cluster with JobManager + TaskManagers
- Supports both batch and stream processing
- Direct Kafka source/sink integration
- Write results to Iceberg/Lance tables
- Savepoint/Checkpoint for fault tolerance

**Key Features**:
- Low-latency processing (milliseconds)
- Stateful stream processing
- Event time and watermarking
- Complex event processing (CEP)
- SQL API for stream queries
- Job restart and recovery policies

**Use Cases**:
- Real-time aggregations and transformations
- Stream joining with historical data
- Anomaly detection
- Real-time feature engineering for ML

#### 3. Flowise AI Workflows
**Low-code platform for building AI workflows and LLM applications**

- Drag-and-drop UI for workflow builder
- LangChain framework integration
- Support for multiple LLM providers (OpenAI, Anthropic, etc.)
- Vector store integration (Lance, Pinecone, Weaviate)
- Retrieval-Augmented Generation (RAG) support
- PostgreSQL backend for workflow persistence
- REST API exposure for deployed workflows

**Key Features**:
- Custom tool creation and chaining
- Document ingestion and embedding
- Semantic search capabilities
- Workflow versioning and deployment
- Integration with Trino for data queries
- Integration with MinIO for document storage

**Use Cases**:
- Building AI chatbots
- Document question-answering systems
- Semantic search applications
- RAG-based applications
- Knowledge base integration
- Multi-step AI workflows

### Data Flow

#### Query Execution Flow

1. **Query Submission**
   - Client submits SQL query via HTTPS to Trino Coordinator
   - Authentication via username/password

2. **Query Planning**
   - Coordinator parses and analyzes the query
   - Consults Hive Metastore for table metadata
   - Metastore queries PostgreSQL for schema information
   - Coordinator generates optimized execution plan

3. **Query Execution**
   - Coordinator distributes tasks to Worker nodes
   - Workers read data directly from MinIO via S3 API
   - Workers process data in parallel (filtering, joins, aggregations)
   - Workers apply predicate pushdown and partition pruning

4. **Result Aggregation**
   - Workers stream partial results to Coordinator
   - Coordinator aggregates and orders final results
   - Results returned to client

#### Data Write Flow

1. **Write Command**
   - Client issues INSERT/CREATE TABLE statement
   - Coordinator validates schema against Metastore

2. **Data Writing**
   - Workers write data files to MinIO in appropriate format
   - File formats: Parquet, ORC (based on table type)
   - Data organized by partitions if applicable

3. **Metadata Update**
   - Metastore updates table metadata in PostgreSQL
   - New files and partitions registered
   - Statistics updated for query optimization

### Supported Table Formats

#### Hive Tables
- **Use Case**: Traditional data warehouse tables
- **Format**: Parquet, ORC, Avro
- **Features**: Basic partitioning, bucketing
- **Best For**: Legacy systems, simple analytics

#### Apache Iceberg
- **Use Case**: Modern cloud-native data lakes
- **Features**:
  - Full ACID transactions
  - Time travel and snapshots
  - Schema evolution without rewriting data
  - Partition evolution
  - Hidden partitioning (automatic partition filtering)
- **Best For**: Production data lakes requiring ACID guarantees

#### Delta Lake
- **Use Case**: Databricks-compatible table format
- **Features**:
  - ACID transactions via transaction log
  - Time travel
  - DML operations (UPDATE, DELETE, MERGE)
  - Z-ordering for data clustering
  - Schema enforcement and evolution
- **Best For**: Spark/Databricks ecosystems

#### Lance Format
- **Use Case**: Vector embeddings and ML workloads
- **Features**:
  - Optimized for vector similarity search
  - Efficient storage of high-dimensional arrays
  - Native support for ML data types
  - Column-oriented with vector indexes
- **Best For**: AI/ML applications, semantic search, RAG systems

### Security Architecture

#### Authentication & Authorization
- **Client Authentication**: Password-based (bcrypt hashed)
- **Inter-service Communication**: Shared secret authentication
- **TLS/SSL**: HTTPS for external connections
- **Network Isolation**: Private subnets (cloud deployments)

#### Data Protection
- **Encryption in Transit**: TLS 1.2+ for all external connections
- **Erasure Coding**: Data redundancy in MinIO (2 node failure tolerance)
- **Access Control**: Service-level authentication
- **Secrets Management**: Kubernetes Secrets

### Scalability Features

#### Horizontal Scaling
- **Trino Workers**: Scale workers independently of coordinator
- **MinIO Nodes**: Add nodes to storage cluster for capacity
- **Stateless Services**: Trino workers can scale up/down dynamically

#### Performance Optimization
- **Query Optimization**: Cost-based optimizer, predicate pushdown
- **Caching**: Metadata caching, result caching
- **Partition Pruning**: Skip irrelevant data based on predicates
- **Parallel Processing**: Distributed execution across workers
- **Vectorized Execution**: SIMD operations for data processing

### High Availability

#### Component Redundancy
- **Trino Coordinator**: Single active instance (can be clustered in advanced setups)
- **Trino Workers**: Multiple instances (2+ recommended)
- **MinIO**: 4-node cluster with erasure coding
- **Hive Metastore**: Can be scaled to multiple replicas
- **PostgreSQL**: Single instance (can use managed DB for HA in cloud)

#### Fault Tolerance
- **MinIO**: Tolerates up to N/2 node failures (2 nodes with 4-node setup)
- **Trino**: Worker failures handled by query retry
- **Pod Restart**: Kubernetes automatically restarts failed pods
- **Data Durability**: Persistent volumes for stateful components

### Deployment Variations

| Feature | Minikube | AWS EKS | GCP GKE |
|---------|----------|---------|---------|
| **Cluster Type** | Single-node | Multi-AZ managed | Regional managed |
| **Load Balancer** | NodePort | ELB Classic | GCP External LB |
| **Storage** | Local PV / emptyDir | EBS gp2 | Persistent Disk SSD |
| **Access** | Port-forward | Public endpoint | IAP + Bastion |
| **Certificates** | Self-signed | ACM (recommended) | Google-managed |
| **Autoscaling** | Manual | Cluster Autoscaler | GKE Autoscaler |
| **Monitoring** | kubectl logs | CloudWatch | Cloud Logging |
| **Best For** | Development | Production (AWS) | Production (GCP) |

### Use Cases

#### 1. Data Lakehouse Analytics
- Unified analytics across multiple data sources
- Interactive SQL queries on petabyte-scale data
- Support for structured and semi-structured data
- Schema evolution without downtime

#### 2. Real-Time Analytics (with Kafka + Flink)
- Ingest streaming data via Kafka
- Process and transform in real-time with Flink
- Store processed results in Iceberg/Lance tables
- Query fresh data with Trino for dashboards
- Low-latency insights on continuously updated data

#### 3. AI/ML Pipelines (with Flowise + Lance)
- Build RAG applications with Flowise
- Store embeddings in Lance format
- Semantic search across documents
- Query structured data via Trino for context
- LLM-powered insights and recommendations

#### 4. Streaming Data Pipeline (Kafka → Flink → Trino)
- Event ingestion via Kafka topics
- Stream processing and enrichment with Flink
- Results written to data lake (MinIO)
- Analytics queries with Trino
- Real-time dashboards and alerts

#### 5. Machine Learning Workflows
- Vector embeddings storage with Lance format
- Feature store for ML models
- Model training data preparation
- Inference data serving
- Integration with AI workflows (Flowise)

#### 6. Data Science Workbench
- Interactive exploration with SQL
- Integration with Jupyter notebooks
- Python client for programmatic access
- Support for complex analytics (window functions, aggregations)

#### 7. AI Chatbot with Knowledge Base (Flowise + Trino + MinIO)
- Document upload and embedding (Flowise)
- Vector search for semantic matching (Lance)
- Query structured data from Trino for context
- LLM-based response generation
- REST API for application integration

## Repository Structure

```
AIchemy/
├── aws/              # AWS EKS deployment configurations
│   ├── README.md     # AWS-specific documentation
│   ├── aws-*.sh      # Infrastructure setup scripts
│   └── aws-*.yml     # Kubernetes manifests
├── gcp/              # GCP GKE deployment configurations
│   ├── README.md     # GCP-specific documentation
│   ├── gcp-*.sh      # Infrastructure setup scripts
│   └── gcp-*.yml     # Kubernetes manifests
├── minikube/         # Minikube local deployment
│   ├── README.md     # Minikube-specific documentation
│   ├── mk-*.yml      # Kubernetes manifests
│   └── mk-notes.md   # Operational notes and commands
├── python/           # Python client examples
│   ├── pip.txt       # Python dependencies
│   └── trino_client_*.py  # Example clients
└── README.md         # This file

```

## Quick Start

### Choose Your Environment

1. **Local Development (Minikube)**
   - See [minikube/README.md](minikube/README.md)
   - Requires: 8GB RAM, 4 CPUs, 40GB disk
   - Setup time: ~10 minutes (core) / ~15 minutes (with optional components)

2. **AWS Production (EKS)**
   - See [aws/README.md](aws/README.md)
   - Requires: AWS account with billing enabled
   - Setup time: ~20 minutes (core) / ~30 minutes (with optional components)

3. **GCP Production (GKE)**
   - See [gcp/README.md](gcp/README.md)
   - Requires: GCP account with billing enabled
   - Setup time: ~15 minutes (core) / ~25 minutes (with optional components)

### Optional Components

Each deployment environment supports optional components:

- **Kafka**: Enable real-time data streaming (recommended for event-driven architectures)
- **Flink Kubernetes Operator**: Add stream processing capabilities (recommended for real-time transformations)
- **Flowise**: Add AI workflow builder (recommended for LLM-based applications)

Optional components are deployed separately and can be enabled/disabled independently. See environment-specific README files for deployment instructions.

### Basic Operations

Once deployed, you can:

```sql
-- Show available catalogs
SHOW CATALOGS;

-- Create Iceberg table
CREATE SCHEMA iceberg.analytics;
CREATE TABLE iceberg.analytics.events (
    event_id BIGINT,
    user_id BIGINT,
    event_time TIMESTAMP,
    properties MAP(VARCHAR, VARCHAR)
);

-- Insert data
INSERT INTO iceberg.analytics.events VALUES 
    (1, 1001, CURRENT_TIMESTAMP, MAP(ARRAY['action'], ARRAY['login']));

-- Query with time travel (Iceberg)
SELECT * FROM iceberg.analytics.events FOR VERSION AS OF 12345;

-- Vector similarity search (Lance)
CREATE TABLE lance.embeddings.docs (
    id INTEGER,
    content VARCHAR,
    embedding ARRAY(DOUBLE)
);
```

## Technology Stack

- **Query Engine**: Trino (latest)
- **Metadata Catalog**: Apache Hive Metastore 4.0.0
- **Database**: PostgreSQL 15
- **Object Storage**: MinIO (S3-compatible)
- **Orchestration**: Kubernetes
- **Table Formats**: Apache Hive, Apache Iceberg, Delta Lake, Lance

## Contributing

Contributions are welcome! Please ensure:
- Code follows existing patterns
- Documentation is updated
- Tested on at least one deployment target

## License

See [LICENCE](LICENCE) file for details.

