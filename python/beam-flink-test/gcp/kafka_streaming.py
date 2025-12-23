#!/usr/bin/env python3
"""
Apache Beam Kafka Streaming - Legge da Kafka, processa e scrive su MinIO/Cloud Storage
"""
import argparse
import json
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.io.kafka import ReadFromKafka, WriteToKafka
import logging

def parse_kafka_message(element):
    """Parse del messaggio JSON da Kafka"""
    try:
        key, value = element
        data = json.loads(value.decode('utf-8'))
        return data
    except Exception as e:
        logging.error(f"Errore nel parsing: {e}")
        return None

def enrich_data(data):
    """Arricchisce i dati con calcoli aggiuntivi"""
    if data is None:
        return None
    
    # Esempio: aggiungi temperatura in Fahrenheit
    if 'data' in data and 'temperature' in data['data']:
        temp_c = data['data']['temperature']
        temp_f = (temp_c * 9/5) + 32
        data['data']['temperature_fahrenheit'] = round(temp_f, 2)
    
    return data

def format_for_output(data):
    """Formatta i dati per l'output"""
    if data is None:
        return None
    
    return json.dumps(data, ensure_ascii=False)

def run(argv=None):
    """Esegue la pipeline di streaming"""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--bootstrap-servers',
        dest='bootstrap_servers',
        default='kafka-0.kafka-headless.kafka.svc.cluster.local:9092',
        help='Kafka bootstrap servers'
    )
    parser.add_argument(
        '--input-topic',
        dest='input_topic',
        default='test-topic',
        help='Kafka input topic'
    )
    parser.add_argument(
        '--output-topic',
        dest='output_topic',
        default='enriched-topic',
        help='Kafka output topic'
    )
    parser.add_argument(
        '--consumer-group',
        dest='consumer_group',
        default='beam-processor',
        help='Kafka consumer group ID'
    )
    
    known_args, pipeline_args = parser.parse_known_args(argv)
    
    pipeline_options = PipelineOptions(pipeline_args)
    
    print(f"Bootstrap servers: {known_args.bootstrap_servers}")
    print(f"Input topic: {known_args.input_topic}")
    print(f"Output topic: {known_args.output_topic}")
    print(f"Consumer group: {known_args.consumer_group}")
    
    with beam.Pipeline(options=pipeline_options) as p:
        
        # Leggi da Kafka
        messages = (
            p 
            | 'ReadFromKafka' >> ReadFromKafka(
                consumer_config={
                    'bootstrap.servers': known_args.bootstrap_servers,
                    'group.id': known_args.consumer_group,
                    'auto.offset.reset': 'earliest'
                },
                topics=[known_args.input_topic],
                with_metadata=False
            )
        )
        
        # Processa i messaggi
        processed = (
            messages
            | 'ParseJSON' >> beam.Map(parse_kafka_message)
            | 'FilterNone' >> beam.Filter(lambda x: x is not None)
            | 'EnrichData' >> beam.Map(enrich_data)
            | 'FormatOutput' >> beam.Map(format_for_output)
            | 'FilterNoneAgain' >> beam.Filter(lambda x: x is not None)
        )
        
        # Log per debug
        processed | 'PrintToConsole' >> beam.Map(
            lambda x: logging.info(f"Processed: {x}")
        )
        
        # Scrivi su Kafka
        (
            processed
            | 'EncodeForKafka' >> beam.Map(lambda x: (b'', x.encode('utf-8')))
            | 'WriteToKafka' >> WriteToKafka(
                producer_config={'bootstrap.servers': known_args.bootstrap_servers},
                topic=known_args.output_topic
            )
        )

if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run()
