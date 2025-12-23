# Kafka Test Scripts

Script Python per testare Kafka su Minikube.

## Installazione dipendenze

```bash
pip install -r pip.txt
```

## Utilizzo

### 1. Avvia il port-forward di Kafka (in un terminale separato)

```bash
kubectl port-forward svc/kafka 30092:9092 -n kafka
```

Oppure usa direttamente il NodePort di Minikube:

```bash
minikube service kafka -n kafka --url
```

### 2. Avvia il Consumer (in un terminale)

```bash
python kafka_consumer.py
```

Il consumer si metterà in ascolto e aspetterà i messaggi.

### 3. Avvia il Producer (in un altro terminale)

```bash
python kafka_producer.py
```

Il producer invierà 10 messaggi di test al topic `test-topic`.

## Configurazione

Modifica le variabili nei file se necessario:

- `KAFKA_BOOTSTRAP_SERVERS`: Lista dei server Kafka
- `TOPIC_NAME`: Nome del topic
- `GROUP_ID`: ID del consumer group (solo per consumer)

## Note

- Il consumer usa `auto_offset_reset='earliest'` per leggere dall'inizio
- Il producer usa `acks='all'` per garantire la scrittura su tutte le repliche
- I messaggi sono serializzati/deserializzati in JSON
