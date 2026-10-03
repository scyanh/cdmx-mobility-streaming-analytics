"""Entry point for the Dataflow job; see infra/run_dataflow.sh."""

import logging

from mobility_pipeline.pipeline import run

if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()
