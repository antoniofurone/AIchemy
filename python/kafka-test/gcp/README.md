# Kafka test (GCP)

Client di test per Kafka su GKE con accesso interno (DNS headless) ed esterno (LoadBalancer per-broker).

## Prerequisiti
- Cluster GKE con deployment da `gcp/gcp-kafka-ha.yml` applicato.
- Servizi `kafka-0-external` e `kafka-1-external` pronti con IP/DNS.
- Python 3.10+ e `confluent-kafka==2.3.0` installato:

```bash
pip install -r python/kafka-test/gcp/pip.txt
```

## Bootstrap servers
Risoluzione ordine:
1. Argomento CLI `--bootstrap`
2. Env `KAFKA_BOOTSTRAP_SERVERS`
3. Env `KAFKA_EXTERNAL_BROKERS` (es. `IP1:9094,IP2:9094`)
4. Env `KAFKA_INTERNAL_BROKERS`
5. Default interno headless: `kafka-0.kafka-headless.kafka.svc.cluster.local:9092,kafka-1.kafka-headless.kafka.svc.cluster.local:9092`

## Esempi

### Interno GKE (pod dentro il cluster)
```bash
python python/kafka-test/gcp/kafka_producer.py --bootstrap "kafka-0.kafka-headless.kafka.svc.cluster.local:9092,kafka-1.kafka-headless.kafka.svc.cluster.local:9092" --topic test-topic --count 5
python python/kafka-test/gcp/kafka_consumer.py --bootstrap "kafka-0.kafka-headless.kafka.svc.cluster.local:9092,kafka-1.kafka-headless.kafka.svc.cluster.local:9092" --topic test-topic --group test-consumer-gcp
```

### Esterno a GKE (Internet)
```bash
export KAFKA_EXTERNAL_BROKERS="34.77.51.1:9094,34.38.133.222:9094"
python python/kafka-test/gcp/kafka_producer.py --topic test-topic --count 5
python python/kafka-test/gcp/kafka_consumer.py --topic test-topic --group test-consumer-gcp
```

Oppure passare direttamente `--bootstrap`:
```bash
python python/kafka-test/gcp/kafka_producer.py --bootstrap "<BROKER0_IP>:9094,<BROKER1_IP>:9094"
python python/kafka-test/gcp/kafka_consumer.py --bootstrap "<BROKER0_IP>:9094,<BROKER1_IP>:9094"
```

## Note
- Porta esterna: 9094 (listener `EXTERNAL`).
- Porta interna: 9092 (listener `PLAINTEXT`).
- Per IP statici su GCP, usa `spec.loadBalancerIP` sui servizi `kafka-*-external`.
