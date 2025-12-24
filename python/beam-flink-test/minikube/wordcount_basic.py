#!/usr/bin/env python3
"""
Apache Beam WordCount - Esempio base con Flink Runner
"""
import argparse
import logging
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions

logging.basicConfig(level=logging.DEBUG)

def run(argv=None):
    """Esegue la pipeline WordCount"""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--input',
        dest='input',
        default='gs://dataflow-samples/shakespeare/kinglear.txt',
        help='Input file to process.'
    )
    parser.add_argument(
        '--output',
        dest='output',
        required=True,
        help='Output file to write results to.'
    )
    known_args, pipeline_args = parser.parse_known_args(argv)
    
    # Configurazione pipeline
    pipeline_options = PipelineOptions(pipeline_args)
    
    print(f"Input: {known_args.input}")
    print(f"Output: {known_args.output}")
    print(f"Pipeline options: {pipeline_options.get_all_options()}")
    
    # Crea pipeline
    with beam.Pipeline(options=pipeline_options) as p:
        
        # Leggi le righe dal file
        lines = p | 'Read' >> beam.io.ReadFromText(known_args.input)
        
        # Conta le parole
        counts = (
            lines
            | 'Split' >> beam.FlatMap(lambda line: line.split())
            | 'PairWithOne' >> beam.Map(lambda word: (word, 1))
            | 'GroupAndSum' >> beam.CombinePerKey(sum)
        )
        
        # Formatta output
        output = counts | 'Format' >> beam.MapTuple(lambda word, count: f'{word}: {count}')
        
        # Scrivi risultati
        output | 'Write' >> beam.io.WriteToText(known_args.output)

if __name__ == '__main__':
    run()
