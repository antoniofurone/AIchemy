#!/usr/bin/env python3
"""
Kafka Producer (GCP) - Supporta client interni GKE e client esterni
- Risolve automaticamente i bootstrap servers da env o argomenti
- Esterno: usa i LoadBalancer per-broker su porta 9094
- Interno: usa i DNS headless del cluster su porta 9092
"""
from confluent_kafka import Producer
import json
import time
from datetime import datetime
import os
import argparse
import socket
import logging

# Setup logging dettagliato
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

DEFAULT_INTERNAL_BOOTSTRAP = (
    "kafka-0.kafka-headless.kafka.svc.cluster.local:9092,"
    "kafka-1.kafka-headless.kafka.svc.cluster.local:9092"
)

TOPIC_NAME_DEFAULT = "test-topic"


def resolve_bootstrap(cli_bootstrap: str | None) -> str:
    """Risolvi i bootstrap servers in quest'ordine:
    1) Argomento CLI --bootstrap
    2) Env KAFKA_BOOTSTRAP_SERVERS
    3) Env KAFKA_EXTERNAL_BROKERS (es. "IP1:9094,IP2:9094")
    4) Env KAFKA_INTERNAL_BROKERS (es. DNS headless)
    5) Default interno GKE
    """
    if cli_bootstrap:
        bootstrap = cli_bootstrap
    else:
        env_bootstrap = os.environ.get("KAFKA_BOOTSTRAP_SERVERS")
        if env_bootstrap:
            bootstrap = env_bootstrap
        else:
            external = os.environ.get("KAFKA_EXTERNAL_BROKERS")
            if external:
                bootstrap = external
            else:
                internal = os.environ.get("KAFKA_INTERNAL_BROKERS")
                if internal:
                    bootstrap = internal
                else:
                    bootstrap = DEFAULT_INTERNAL_BOOTSTRAP
    
    # Rimuovi le virgolette (se passate da shell)
    bootstrap = bootstrap.strip('"').strip("'")
    return bootstrap


def test_connectivity(bootstrap_servers: str) -> bool:
    """Testa connettività ai broker Kafka"""
    brokers = bootstrap_servers.split(",")
    logger.info(f"Test di connettività a {len(brokers)} broker(s)...")
    
    all_ok = True
    for broker in brokers:
        broker = broker.strip()
        host, port = broker.split(":")
        port = int(port)
        
        logger.info(f"  Testando {host}:{port}...")
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((host, port))
            sock.close()
            
            if result == 0:
                logger.info(f"    ✓ {host}:{port} raggiungibile")
            else:
                logger.warning(f"    ✗ {host}:{port} NON raggiungibile (errno: {result})")
                all_ok = False
        except socket.gaierror as e:
            logger.error(f"    ✗ {host}: Impossibile risolvere hostname ({e})")
            all_ok = False
        except Exception as e:
            logger.error(f"    ✗ {host}:{port}: Errore ({e})")
            all_ok = False
    
    return all_ok


def delivery_callback(err, msg):
    """Callback chiamato quando un messaggio viene confermato"""
    if err:
        logger.error(f"Errore nella consegna del messaggio: {err}")
    else:
        logger.debug(
            f"Messaggio confermato: topic={msg.topic()}, "
            f"partition={msg.partition()}, offset={msg.offset()}"
        )


def create_producer(bootstrap_servers: str) -> Producer:
    """Crea un producer Kafka"""
    logger.info(f"Creazione producer con bootstrap servers: {bootstrap_servers}")
    conf = {
        "bootstrap.servers": bootstrap_servers,
        "acks": "all",  # Attendi conferma da tutti i broker
        "retries": 3,
        "socket.timeout.ms": 10000,  # Timeout connessione 10sec
        "connections.max.idle.ms": 30000,  # Chiudi connessioni inattive
        "request.timeout.ms": 10000,  # Timeout richiesta
        "debug": "broker,topic",  # Debug dettagliato
    }
    logger.debug(f"Configurazione producer: {conf}")
    return Producer(conf)


def send_messages(producer: Producer, topic_name: str, num_messages: int = 10):
    """Invia messaggi al topic"""
    logger.info(f"Invio di {num_messages} messaggi al topic '{topic_name}'")

    for i in range(num_messages):
        # Crea un messaggio
        message = {
            "id": i,
            "timestamp": datetime.now().isoformat(),
            "message": f"Messaggio numero {i}",
            "data": {"temperature": 20 + (i % 10), "humidity": 50 + (i % 20)},
        }

        key = f"key-{i}"
        try:
            logger.debug(f"Invio messaggio {i}/{num_messages}...")
            producer.produce(
                topic_name,
                key=key.encode("utf-8"),
                value=json.dumps(message).encode("utf-8"),
                callback=delivery_callback,
            )
            producer.poll(0)
        except Exception as e:
            logger.error(f"Errore nell'invio del messaggio {i}: {e}")

        time.sleep(1)

    # Flush con timeout (max 30 secondi)
    logger.info("In attesa di conferma messaggi (flush)...")
    remaining = producer.flush(timeout=30)
    if remaining > 0:
        logger.warning(f"{remaining} messaggi non confermati dopo timeout")
    else:
        logger.info("Tutti i messaggi confermati!")


def parse_args():
    p = argparse.ArgumentParser(description="Kafka Producer GCP")
    p.add_argument("--bootstrap", help="Lista brokers es. host1:port,host2:port")
    p.add_argument("--topic", default=TOPIC_NAME_DEFAULT, help="Nome del topic")
    p.add_argument("--count", type=int, default=10, help="Numero di messaggi")
    return p.parse_args()


def main():
    args = parse_args()
    bootstrap = resolve_bootstrap(args.bootstrap)
    topic_name = args.topic

    logger.info("=" * 50)
    logger.info("Kafka Producer (GCP)")
    logger.info("=" * 50)
    logger.info(f"Bootstrap servers: {bootstrap}")
    logger.info(f"Topic: {topic_name}")
    logger.info(f"Numero messaggi: {args.count}")

    # Test connettività
    if not test_connectivity(bootstrap):
        logger.error("Impossibile raggiungere i broker Kafka!")
        logger.error("Verifica:")
        logger.error("  1. IP/DNS dei broker")
        logger.error("  2. Porta (9092 interno, 9094 esterno)")
        logger.error("  3. Firewall/Security groups su GCP")
        logger.error("  4. Cluster GKE è online?")
        return

    try:
        logger.info("Creazione producer...")
        producer = create_producer(bootstrap)
        logger.info("✓ Producer creato!")
        
        send_messages(producer, topic_name, num_messages=args.count)
        logger.info("=" * 50)
        logger.info("✓ Completato!")
        logger.info("=" * 50)
    except Exception as e:
        logger.error(f"Errore critico: {e}", exc_info=True)


if __name__ == "__main__":
    main()
