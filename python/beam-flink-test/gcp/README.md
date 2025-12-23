# Apache Beam con Flink Runner su GCP/GKE

Script Python per eseguire job Apache Beam su Flink cluster in GCP/GKE.

## Installazione

```bash
pip install -r requirements.txt
```

## 1. WordCount Base (Batch)

Esempio classico di conteggio parole.

### Esecuzione locale (DirectRunner)

```bash
python wordcount_basic.py \
  --input gs://dataflow-samples/shakespeare/kinglear.txt \
  --output /tmp/wordcount_output
```

Esempio su GCP (con Cloud Storage):
```bash
python wordcount_basic.py \
  --input gs://your-bucket/input/sample.txt \
  --output gs://your-bucket/output/wordcount
```

### Esecuzione su Flink (GKE)

**Passo 1:** Ottieni l'IP del Beam Job Server:

```bash
kubectl get svc beam-job-server-external -n flink
# Prendi l'EXTERNAL-IP (se LoadBalancer pubblico) o INTERNAL-IP (se interno)
```

**Opzione A - LoadBalancer Interno (consigliato per sicurezza):**
- L'IP sarà accessibile solo dalla tua VPC/GKE cluster
- Se lavori da locale, usa un bastion host o Cloud Shell

**Opzione B - LoadBalancer Pubblico:**
- Modifica [gcp-flink.yml](../../../gcp/gcp-flink.yml): cambia `networking.gke.io/load-balancer-type: "Internal"` in `"External"`
- **Attenzione:** Espone il Job Server pubblicamente su Internet

**Opzione C - Port-forward (alternativa):**
```bash
kubectl port-forward svc/beam-job-server 8098:8098 8097:8097 8099:8099 -n flink
```

**Passo 2:** Esegui il job:

```bash
# Con LoadBalancer (usa l'EXTERNAL-IP ottenuto sopra)
python wordcount_basic.py \
  --runner=FlinkRunner \
  --job_endpoint=<BEAM-JOB-SERVER-IP>:8098 \
  --environment_type=LOOPBACK \
  --output=gs://your-bucket/output/wordcount
```

Esempio con IP effettivo (LoadBalancer interno):
```bash
python wordcount_basic.py \
  --runner=FlinkRunner \
  --job_endpoint=10.128.0.45:8098 \
  --environment_type=LOOPBACK \
  --output=gs://test-alchemy-01/output/wordcount
```

Esempio Windows con port-forward:
```bash
python wordcount_basic.py ^
  --runner=FlinkRunner ^
  --job_endpoint=localhost:8098 ^
  --environment_type=LOOPBACK ^
  --output=gs://test-alchemy-01/output/wordcount
```

**Note:**
- `job_endpoint` punta al **Beam Job Server** (porta 8098), non al Flink JobManager
- Le tre porte (8098, 8097, 8099) vengono esposte dal LoadBalancer
- `LOOPBACK` environment: Il worker SDK Python gira nello stesso processo del client


## 2. Kafka Streaming (Streaming)

Pipeline che legge da Kafka, arricchisce i dati e scrive su un altro topic.

### Prerequisiti

Port-forward di Kafka (se non hai accesso esterno):

```bash
kubectl port-forward kafka-0 9092:9092 -n kafka
```

Oppure usa il servizio Kafka disponibile nel cluster.

### Esecuzione locale (DirectRunner)

```bash
python kafka_streaming.py \
  --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --input-topic=test-topic \
  --output-topic=enriched-topic \
  --consumer-group=beam-processor
```

### Esecuzione su Flink (Streaming Mode)

```bash
# Con LoadBalancer
python kafka_streaming.py \
  --runner=FlinkRunner \
  --job_endpoint=<BEAM-JOB-SERVER-IP>:8098 \
  --streaming \
  --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --input-topic=test-topic \
  --output-topic=enriched-topic \
  --consumer-group=beam-processor-flink

# Con port-forward
python kafka_streaming.py \
  --runner=FlinkRunner \
  --job_endpoint=localhost:8098 \
  --streaming \
  --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --input-topic=test-topic \
  --output-topic=enriched-topic \
  --consumer-group=beam-processor-flink
```

## Monitoraggio

Accedi alla Flink UI per vedere i job in esecuzione:

```bash
# Via port-forward
kubectl port-forward svc/flink-jobmanager-ui 8081:8081 -n flink

# Oppure tramite LoadBalancer (se configurato)
kubectl get svc flink-jobmanager-ui -n flink -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Poi apri http://localhost:8081 o http://EXTERNAL-IP:8081

## Opzioni Flink Runner

- `--runner=FlinkRunner`: Usa Flink invece del DirectRunner
- `--job_endpoint=localhost:8098`: Indirizzo del Beam Job Server (consigliato)
- `--flink_master=localhost:8081`: Indirizzo del JobManager (legacy, non consigliato)
- `--streaming`: Abilita modalità streaming (per pipeline infinite)
- `--environment_type=LOOPBACK`: Esegue worker SDK nello stesso processo
- `--parallelism=2`: Numero di task paralleli
- `--flink_submit_uber_jar`: Carica JAR completo invece di dipendenze separate

**Importante:** In GKE, usa sempre `--job_endpoint` invece di `--flink_master` per sfruttare il Beam Job Server.

## Note

- Il **DirectRunner** esegue localmente ed è ottimo per debug
- Il **FlinkRunner** distribuisce il job sul cluster Flink in GKE
- Per job streaming usa sempre `--streaming`
- La modalità LOOPBACK è più semplice per GKE (no Docker SDK harness)
- Per Cloud Storage, assicurati che il cluster GKE abbia i permessi necessari (Workload Identity)

## Troubleshooting

### Errore: gRPC connection failed / UNKNOWN status

**Sintomo:**
```
grpc._channel._MultiThreadedRendezvous: RPC that terminated with status = StatusCode.UNKNOWN
Error received from peer ipv6:[::1]:5xxxx
```

**⚠️ Importante:** Se **puoi raggiungere la Flink UI**, il problema NON è di rete ma di configurazione SDK/Job Server.

**Cause possibili e soluzioni:**

1. **Flink JobManager non ha Job Server SDK abilitato (causa più probabile):**
   ```bash
   # Verifica i log - cerca "job.server" o "8099"
   kubectl logs -n flink deployment/flink-jobmanager | grep -i "job\|8099\|server"
   ```
   
   Se il job server non è in ascolto, devi abilitarlo nel `gcp-flink.yml`:
   ```yaml
   flink-conf.yaml: |
     jobmanager.rpc.address: flink-jobmanager
     # Aggiungi queste linee:
     rest.port: 8081
     rest.address: 0.0.0.0
   ```

2. **Prova con DOCKER environment (se Docker è disponibile):**
   ```bash
   python wordcount_basic.py \
     --runner=FlinkRunner \
     --flink_master=35.205.212.239:8081 \
     --environment_type=DOCKER \
     --docker_registry_push_url=gcr.io/your-project \
     --output=gs://test-alchemy-01/output/wordcount
   ```

3. **Soluzione temporanea: Usa DirectRunner:**
   ```bash
   python wordcount_basic.py \
     --input gs://dataflow-samples/shakespeare/kinglear.txt \
     --output gs://test-alchemy-01/output/wordcount_direct
   ```
   Questo esegue localmente e scrive il risultato su GCS (no Flink needed).

4. **Se hai accesso SSH al cluster, verifica il Job Server:**
   ```bash
   kubectl port-forward svc/flink-jobmanager 8099:8099 -n flink
   # In un altro terminale:
   curl http://localhost:8099/api/v1/jobs
   # Se risponde con JSON, il job server funziona
   ```

5. **Prova con localhost e port-forward:**
   ```bash
   # Terminale 1
   kubectl port-forward svc/flink-jobmanager 8081:8081 -n flink
   
   # Terminale 2
   python wordcount_basic.py \
     --runner=FlinkRunner \
     --flink_master=localhost:8081 \
     --environment_type=LOOPBACK \
     --output=gs://test-alchemy-01/output/wordcount
   ```

### Errore: Cloud Storage (GCS) not accessible

Se i file di output non vengono scritti su GCS:

```bash
# Verifica Workload Identity
kubectl describe serviceaccount default -n flink

# Controlla i binding
gcloud iam service-accounts get-iam-policy <SERVICE-ACCOUNT>

# Verifica i permessi GCS
gsutil ls gs://your-bucket/
```

### Errore: Kafka connection failed

```bash
# Verifica che Kafka sia raggiungibile
kubectl get pods -n kafka

# Prova port-forward di Kafka
kubectl port-forward kafka-0 9092:9092 -n kafka

# Usa localhost:9092 se il pod è locale
```

### Debug generale

Se il job fallisce:

1. Controlla i log di Flink: `kubectl logs -n flink deployment/flink-jobmanager -f`
2. Verifica TaskManager: `kubectl get pods -n flink -o wide`
3. Controlla la Flink UI per dettagli errori: http://localhost:8081
4. Abilita debug logging aggiungendo `--log_level=DEBUG` al comando

## Deploy su GKE

```bash
# Crea il cluster GKE (se non esiste)
gcloud container clusters create flink-cluster \
  --zone us-central1-a \
  --num-nodes 3 \
  --enable-ip-alias \
  --enable-stackdriver-kubernetes

# Applica i manifesti Flink
kubectl apply -f gcp-flink.yml

# Verifica
kubectl get pods -n flink
kubectl get svc -n flink
```
