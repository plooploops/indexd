#!/bin/bash
# entrypoint bash script for indexd to healthcheck postgres to make sure that 
# postgres is ready before indexd tries to access its database

## try to install python util, or else fallback to environment variables.
python3 -m pip install cdispyutils

sleep 2
until (python check_db.py); do echo "Postgres not available - sleeping"; sleep 2; done;
echo "postgres is ready"

python /indexd/bin/index_admin.py create --username indexd_client --password indexd_client_pass

# activate virtual env
. /indexd/py-venv/bin/activate
# TODO check if the metrics endpoint is up before curling.
# This is a workaround for scraping stdout for metrics.
/dockerrun.sh & while true; do curl -X GET ${METRICS_URL}; sleep ${METRICS_CHECK_INTERVAL}; done
