#!/usr/bin/env python3
"""
Kafka Producer - Invia messaggi a un topic Kafka
"""
from confluent_kafka import Producer
import json
import time
from datetime import datetime

# Configurazione Kafka
KAFKA_BOOTSTRAP_SERVERS = 'kafka-0.kafka-headless.kafka.svc.cluster.local:9092'
TOPIC_NAME = 'test-topic'

def delivery_callback(err, msg):
    """Callback chiamato quando un messaggio viene confermato"""
    if err:
        print(f"✗ Errore nella consegna del messaggio: {err}")
    else:
        print(f"✓ Messaggio inviato: topic={msg.topic()}, "
              f"partition={msg.partition()}, offset={msg.offset()}")

def create_producer():
    """Crea un producer Kafka"""
    conf = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'acks': 'all',  # Attendi conferma da tutti i broker
        'retries': 3
    }
    return Producer(conf)

def send_messages(producer, num_messages=10):
    """Invia messaggi al topic"""
    print(f"Invio di {num_messages} messaggi al topic '{TOPIC_NAME}'...\n")
    
    for i in range(num_messages):
        # Crea un messaggio
        message = {
            'id': i,
            'timestamp': datetime.now().isoformat(),
            'message': f'Messaggio numero {i}',
            'data': {
                'temperature': 20 + (i % 10),
                'humidity': 50 + (i % 20)
            }
        }
        
        # Invia il messaggio
        key = f'key-{i}'
        try:
            producer.produce(
                TOPIC_NAME,
                key=key.encode('utf-8'),
                value=json.dumps(message).encode('utf-8'),
                callback=delivery_callback
            )
            # Trigger callback
            producer.poll(0)
        except Exception as e:
            print(f"✗ Errore nell'invio del messaggio {i}: {e}")
        
        # Pausa tra messaggi
        time.sleep(1)
    
    # Attendi che tutti i messaggi siano stati inviati
    producer.flush()

def main():
    print("=== Kafka Producer ===")
    print(f"Bootstrap servers: {KAFKA_BOOTSTRAP_SERVERS}")
    print(f"Topic: {TOPIC_NAME}\n")
    
    try:
        # Crea producer
        producer = create_producer()
        print("Producer connesso!\n")
        
        # Invia messaggi
        send_messages(producer, num_messages=10)
        
        print("\n✓ Tutti i messaggi sono stati inviati!")
        
    except Exception as e:
        print(f"\n✗ Errore: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
