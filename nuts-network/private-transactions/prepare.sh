#!/usr/bin/env bash

set -e

source ../../util.sh

echo "------------------------------------"
echo "Cleaning up running Docker containers and volumes, and key material..."
echo "------------------------------------"

docker compose down
docker compose rm -f -v
rm -rf ./node-*/data
if [[ $OSTYPE == 'darwin'* ]]; then
  # sed works different on MacOS; see https://stackoverflow.com/questions/19456518
  sed -i '' -e '/nodedid: did:nuts:/d' ./node-*/nuts.yaml
else
  sed -i '/nodedid: did:nuts:/d' ./node-*/nuts.yaml
fi

echo "------------------------------------"
echo "Starting Docker containers..."
echo "------------------------------------"

docker compose up -d

waitForDCService nodeA
waitForDCService nodeB

# Wait for Nuts Network nodes to build connections
sleep 5

echo "------------------------------------"
echo "Creating NodeDIDs..."
echo "------------------------------------"

didNodeA=$(setupNode "http://localhost:11323" "nodeA:5555")
printf "NodeDID for node-a: %s\n" "$didNodeA"

# Wait for the transactions to be processed (will be the root transaction for both nodes)
sleep 5

didNodeB=$(setupNode "http://localhost:21323" "nodeB:5555")
printf "NodeDID for node-b: %s\n" "$didNodeB"

# Wait for the transactions to be processed
sleep 5

echo "  nodedid: $didNodeA" >> node-A/nuts.yaml
echo "  nodedid: $didNodeB" >> node-B/nuts.yaml

docker compose stop
