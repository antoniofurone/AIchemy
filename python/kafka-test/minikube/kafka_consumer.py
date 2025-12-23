#!/usr/bin/env python3
"""
Kafka Consumer - Legge messaggi da un topic Kafka
"""
from confluent_kafka import Consumer, KafkaException
import json
import signal
import sys
import time

# Configurazione Kafka
KAFKA_BOOTSTRAP_SERVERS = 'kafka-0.kafka-headless.kafka.svc.cluster.local:9092'
TOPIC_NAME = 'test-topic'
GROUP_ID = 'test-consumer-group-v2'  # Cambia per resettare l'offset

# Flag per gestire l'interruzione
running = True

def signal_handler(sig, frame):
    """Gestisce CTRL+C per chiusura pulita"""
    global running
    print("\n\nInterruzione ricevuta, chiusura consumer...")
    running = False

def create_consumer():
    """Crea un consumer Kafka"""
    conf = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'group.id': GROUP_ID,
        'auto.offset.reset': 'earliest',
        'enable.auto.commit': False  # Disabilita auto-commit per debug
    }
    consumer = Consumer(conf)
    
    # Ottieni metadata del topic
    from confluent_kafka import TopicPartition
    
    print(f"Connessione a Kafka...")
    metadata = consumer.list_topics(TOPIC_NAME, timeout=10)
    
    if TOPIC_NAME not in metadata.topics:
        print(f"✗ Topic '{TOPIC_NAME}' non trovato!")
        return None
    
    topic_metadata = metadata.topics[TOPIC_NAME]
    partitions = topic_metadata.partitions
    
    print(f"✓ Topic '{TOPIC_NAME}' trovato con {len(partitions)} partizioni")
    
    # Assegna manualmente tutte le partizioni dal beginning
    partitions_to_assign = [TopicPartition(TOPIC_NAME, p, 0) for p in partitions.keys()]
    consumer.assign(partitions_to_assign)
    
    print(f"✓ Partizioni assegnate: {[p.partition for p in partitions_to_assign]}")
    
    return consumer

def consume_messages(consumer):
    """Consuma messaggi dal topic"""
    print(f"\nIn ascolto sul topic '{TOPIC_NAME}'...")
    print("Premi CTRL+C per fermare\n")
    
    message_count = 0
    poll_count = 0
    
    try:
        while running:
            msg = consumer.poll(timeout=1.0)
            poll_count += 1
            
            if poll_count % 10 == 0:
                print(f"[DEBUG] Poll #{poll_count}, messaggi ricevuti: {message_count}")
            
            if msg is None:
                continue
            
            if msg.error():
                print(f"[ERROR] {msg.error()}")
                if msg.error().code() == -191:  # _PARTITION_EOF
                    print("[INFO] Fine della partizione raggiunta")
                    continue
                raise KafkaException(msg.error())
            
            message_count += 1
            
            # Deserializza il messaggio
            key = msg.key().decode('utf-8') if msg.key() else None
            value = json.loads(msg.value().decode('utf-8'))
            
            print(f"\n--- Messaggio {message_count} ---")
            print(f"Topic: {msg.topic()}")
            print(f"Partition: {msg.partition()}")
            print(f"Offset: {msg.offset()}")
            print(f"Key: {key}")
            print(f"Timestamp: {msg.timestamp()[1]}")
            print(f"Value: {json.dumps(value, indent=2)}")
            print("-" * 50)
            
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"\n✗ Errore: {e}")
        import traceback
        traceback.print_exc()
    
    return message_count

def main():
    print("=== Kafka Consumer ===")
    print(f"Bootstrap servers: {KAFKA_BOOTSTRAP_SERVERS}")
    print(f"Topic: {TOPIC_NAME}")
    print(f"Group ID: {GROUP_ID}")
    
    # Registra il signal handler per CTRL+C
    signal.signal(signal.SIGINT, signal_handler)
    
    consumer = None
    try:
        # Crea consumer
        consumer = create_consumer()
        print("\n✓ Consumer connesso!")
        
        # Consuma messaggi
        message_count = consume_messages(consumer)
        
        print(f"\n✓ Totale messaggi letti: {message_count}")
        
    except Exception as e:
        print(f"\n✗ Errore: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Chiudi il consumer
        if consumer:
            consumer.close()
            print("Consumer chiuso.")

if __name__ == '__main__':
    main()
