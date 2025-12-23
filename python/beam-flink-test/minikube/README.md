# Apache Beam con Flink Runner

Script Python per eseguire job Apache Beam su Flink cluster in Minikube.

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

Esempio Windows:
```bash
python wordcount_basic.py --input C:/Temp/beam-test/sample.txt --output C:/Temp/beam-test/output
```


### Esecuzione su Flink

**Passo 1:** Port-forward del Job Server (tutte le porte necessarie):

```bash
kubectl port-forward svc/beam-job-server 8098:8098 8097:8097 8099:8099 -n flink
```

Le tre porte servono a:

8098: Job submission
8097: Expansion service
8099: Artifact service (per caricare dipendenze Python)

**Passo 2:** Esegui il job:

```bash
python wordcount_basic.py \
  --runner=FlinkRunner \
  --job_endpoint=localhost:8098 \
  --environment_type=LOOPBACK \
  --output=/tmp/wordcount_output
```

Esempio Windows:
```bash
python wordcount_basic.py --runner=FlinkRunner --job_endpoint=localhost:8098 --environment_type=LOOPBACK --output C:/Temp/beam-test/output
```

**Note:**
- `LOOPBACK` environment: Il worker SDK Python gira nello stesso processo del client
- Più semplice di PROCESS e DOCKER per test locali
- Non richiede Python/Docker nei TaskManager Flink
- `PROCESS` environment: Flink esegue il worker SDK Python in un processo separato (non Docker)
- Non richiede Docker installato nei nodi Flink
- Richiede che Python e Apache Beam SDK siano disponibili nei TaskManager

**⚠️ PREREQUISITO:** Devi prima installare Python + Beam SDK nei TaskManager. Esegui:

```bash
# Accedi a un TaskManager pod
kubectl exec -it -n flink deployment/flink-taskmanager -- bash

# Installa Python e Beam SDK
apt-get update && apt-get install -y python3 python3-pip
pip install apache-beam[gcp]>=2.60.0

exit
```

**Oppure ricostruisci i pod con un'immagine custom che include Python (consigliato):**

Crea un Dockerfile:
```dockerfile
FROM flink:1.18.1-scala_2.12-java11
RUN apt-get update && apt-get install -y python3 python3-pip
RUN pip install apache-beam[gcp]>=2.60.0
```

Poi:
```bash
docker build -t flink-beam:1.18.1 .
minikube image load flink-beam:1.18.1  # se usi Minikube

# Aggiorna mk-flink.yml per usare: image: flink-beam:1.18.1
```

**Opzione Legacy (senza Job Server):**

Se vuoi usare il JobManager direttamente (richiede port-forward separato):

```bash
kubectl port-forward svc/flink-jobmanager 8081:8081 -n flink
python wordcount_basic.py \
  --runner=FlinkRunner \
  --flink_master=localhost:8081 \
  --environment_type=LOOPBACK \
  --output=/tmp/wordcount_output
```

## 2. Kafka Streaming (Streaming)

Pipeline che legge da Kafka, arricchisce i dati e scrive su un altro topic.

### Prerequisiti

Port-forward di Kafka:

```bash
kubectl port-forward kafka-0 9092:9092 -n kafka
```

Aggiungi al file hosts (Windows):

```
127.0.0.1 kafka-0.kafka-headless.kafka.svc.cluster.local
```

### Esecuzione locale (DirectRunner)

```bash
python kafka_streaming.py \
  --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --input-topic=test-topic \
  --output-topic=enriched-topic \
  --consumer-group=beam-processor
```

python kafka_streaming.py --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 --input-topic=test-topic --output-topic=enriched-topic --consumer-group=beam-processor


### Esecuzione su Flink (Streaming Mode)

```bash
python kafka_streaming.py \
  --runner=FlinkRunner \
  --flink_master=localhost:8081 \
  --streaming \
  --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 \
  --input-topic=test-topic \
  --output-topic=enriched-topic \
  --consumer-group=beam-processor-flink
```

python kafka_streaming.py --runner=FlinkRunner --flink_master=localhost:8081 --streaming --bootstrap-servers=kafka-0.kafka-headless.kafka.svc.cluster.local:9092 --input-topic=test-topic --output-topic=enriched-topic --consumer-group=beam-processor-flink


## Monitoraggio

Accedi alla Flink UI per vedere i job in esecuzione:

```bash
minikube service flink-jobmanager-ui -n flink --url
# Oppure
kubectl port-forward svc/flink-jobmanager-ui 8081:8081 -n flink
```

Poi apri http://localhost:8081

## Opzioni Flink Runner

- `--runner=FlinkRunner`: Usa Flink invece del DirectRunner
- `--flink_master=localhost:8081`: Indirizzo del JobManager
- `--streaming`: Abilita modalità streaming (per pipeline infinite)
- `--environment_type=LOOPBACK`: Esegue worker SDK nello stesso processo
- `--parallelism=2`: Numero di task paralleli
- `--flink_submit_uber_jar`: Carica JAR completo invece di dipendenze separate

## Note

- Il **DirectRunner** esegue localmente ed è ottimo per debug
- Il **FlinkRunner** distribuisce il job sul cluster Flink
- Per job streaming usa sempre `--streaming`
- La modalità LOOPBACK è più semplice per Minikube (no Docker SDK harness)

## Troubleshooting

Se il job fallisce:

1. Controlla i log di Flink: `kubectl logs -n flink deployment/flink-jobmanager`
2. Verifica TaskManager: `kubectl get pods -n flink`
3. Controlla la Flink UI per dettagli errori
