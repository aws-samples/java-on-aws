#bin/sh

# Check if URL parameter is provided
if [ -z "$1" ]; then
    echo "Error: URL parameter is required"
    echo "Usage: $0 <service-url> [duration] [arrival-rate]"
    exit 1
fi

# Check if URL starts with http:// or https://
if ! echo "$1" | grep -q "^http" ; then
    echo "Error: URL must start with http:// or https://"
    echo "Provided URL: $1"
    exit 1
fi

SVC_URL=$1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$2" ] && [ -n "$3" ]
then
  artillery run --overrides "{\"config\": { \"phases\": [{ \"duration\": $2, \"arrivalRate\": $3 }] } }" \
  -t $SVC_URL -v '{ "url": "/unicorns" }' "$SCRIPT_DIR/benchmark.yaml"
else
  artillery run \
  -t $SVC_URL -v '{ "url": "/unicorns" }' "$SCRIPT_DIR/benchmark.yaml"
fi
