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

id=$(curl --location --request POST $location'/unicorns' \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "20",
    "type": "Animal",
    "size": "Very big"
}' | jq -r '.id')
echo POST ...
echo id=$id
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
echo PUT ...
curl --location --request PUT $location'/unicorns/'$id \
  --header 'Content-Type: application/json' \
  --data-raw '{
    "name": "'"Something-$(date +%s)"'",
    "age": "10",
    "type": "Animal",
    "size": "Small"
}' | jq -r
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
echo DELETE id=$id ...
curl --location --request DELETE $location'/unicorns/'$id | jq
echo GET id=$id ...
curl --location --request GET $location'/unicorns/'$id | jq
