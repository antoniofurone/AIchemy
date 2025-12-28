import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def run():
    flink_master = os.getenv('FLINK_MASTER', 'localhost:8081')
    env_type = os.getenv('BEAM_ENV', 'PROCESS').upper()  # PROCESS by default; set to DOCKER to use SDK containers
    logger.info(f'Connecting to Flink at: {flink_master} (env={env_type})')

    options_list = [
        '--runner=FlinkRunner',
        f'--flink_master={flink_master}',
        '--parallelism=2'
    ]

    if env_type == 'DOCKER':
        options_list.extend([
            '--environment_type=DOCKER',
            '--environment_config=apache/beam_python3.10_sdk:2.60.0'
        ])
    else:
        # Run Python SDK harness as a local process inside TaskManagers
        # Use a plain string command to avoid unhashable list in Beam env config
        options_list.extend([
            '--environment_type=PROCESS',
            '--environment_config={"command": "python3", "args": ["-m", "apache_beam.runners.worker.sdk_worker_main"]}'
        ])

        

    options = PipelineOptions(options_list)

    with beam.Pipeline(options=options) as p:
        (
            p
            | 'Create' >> beam.Create(['Hello', 'World', 'Beam', 'Flink'])
            | 'Upper' >> beam.Map(str.upper)
            | 'Print' >> beam.Map(print)
        )

if __name__ == '__main__':
    run()