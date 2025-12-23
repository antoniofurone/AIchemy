#!/usr/bin/env python3
"""
Kafka Consumer (GCP) - Supporta client interni GKE e client esterni
- Risolve automaticamente i bootstrap servers da env o argomenti
- Esterno: usa i LoadBalancer per-broker su porta 9094
- Interno: usa i DNS headless del cluster su porta 9092
"""
from confluent_kafka import Consumer, KafkaException
import json
import signal
import os
import argparse

DEFAULT_INTERNAL_BOOTSTRAP = (
    "kafka-0.kafka-headless.kafka.svc.cluster.local:9092,"
    "kafka-1.kafka-headless.kafka.svc.cluster.local:9092"
)

TOPIC_NAME_DEFAULT = "test-topic"
GROUP_ID_DEFAULT = "test-consumer-gcp"

running = True


def resolve_bootstrap(cli_bootstrap: str | None) -> str:
    if cli_bootstrap:
        return cli_bootstrap
    env_bootstrap = os.environ.get("KAFKA_BOOTSTRAP_SERVERS")
    if env_bootstrap:
        return env_bootstrap
    external = os.environ.get("KAFKA_EXTERNAL_BROKERS")
    if external:
        return external
    internal = os.environ.get("KAFKA_INTERNAL_BROKERS")
    if internal:
        return internal
    return DEFAULT_INTERNAL_BOOTSTRAP


def signal_handler(sig, frame):
    global running
    print("\n\nInterruzione ricevuta, chiusura consumer...")
    running = False


def create_consumer(bootstrap_servers: str, group_id: str) -> Consumer:
    conf = {
        "bootstrap.servers": bootstrap_servers,
        "group.id": group_id,
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
    }
    return Consumer(conf)


def consume_messages(consumer: Consumer, topic_name: str):
    print(f"\nIn ascolto sul topic '{topic_name}'...")
    print("Premi CTRL+C per fermare\n")

    message_count = 0
    poll_count = 0

    try:
        from confluent_kafka import TopicPartition
        # Ottieni metadata del topic e assegna tutte le partizioni
        metadata = consumer.list_topics(topic_name, timeout=10)
        if topic_name not in metadata.topics:
            print(f"✗ Topic '{topic_name}' non trovato!")
            return 0
        partitions = metadata.topics[topic_name].partitions
        partitions_to_assign = [TopicPartition(topic_name, p, 0) for p in partitions.keys()]
        consumer.assign(partitions_to_assign)
        print(f"✓ Partizioni assegnate: {[p.partition for p in partitions_to_assign]}")

        while running:
            msg = consumer.poll(timeout=1.0)
            poll_count += 1
            if poll_count % 10 == 0:
                print(f"[DEBUG] Poll #{poll_count}, messaggi ricevuti: {message_count}")
            if msg is None:
                continue
            if msg.error():
                print(f"[ERROR] {msg.error()}")
                raise KafkaException(msg.error())
            message_count += 1
            key = msg.key().decode("utf-8") if msg.key() else None
            value = json.loads(msg.value().decode("utf-8"))
            print(f"\n--- Messaggio {message_count} ---")
            print(f"Topic: {msg.topic()}")
            print(f"Partition: {msg.partition()}")
            print(f"Offset: {msg.offset()}")
            print(f"Key: {key}")
            print(f"Timestamp: {msg.timestamp()[1]}")
            print(f"Value: {json.dumps(value, indent=2)}")
            print("-" * 50)
    finally:
        consumer.close()
    return message_count


def parse_args():
    p = argparse.ArgumentParser(description="Kafka Consumer GCP")
    p.add_argument("--bootstrap", help="Lista brokers es. host1:port,host2:port")
    p.add_argument("--topic", default=TOPIC_NAME_DEFAULT, help="Nome del topic")
    p.add_argument("--group", default=GROUP_ID_DEFAULT, help="Group ID")
    return p.parse_args()


def main():
    args = parse_args()
    bootstrap = resolve_bootstrap(args.bootstrap)
    topic_name = args.topic
    group_id = args.group

    print("=== Kafka Consumer (GCP) ===")
    print(f"Bootstrap servers: {bootstrap}")
    print(f"Topic: {topic_name}")
    print(f"Group ID: {group_id}")

    signal.signal(signal.SIGINT, signal_handler)

    try:
        consumer = create_consumer(bootstrap, group_id)
        print("\n✓ Consumer connesso!")
        count = consume_messages(consumer, topic_name)
        print(f"\n✓ Totale messaggi letti: {count}")
    except Exception as e:
        print(f"\n✗ Errore: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
