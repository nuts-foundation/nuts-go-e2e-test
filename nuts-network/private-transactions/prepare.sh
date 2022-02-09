#!/usr/bin/env bash

set -e

source ../../util.sh

function setupNode() {
  local did=$(printf '{
    "selfControl": true,
    "keyAgreement": true,
    "assertionMethod": true,
    "capabilityInvocation": true
  }' | curl -s -X POST "$1/internal/vdr/v1/did" -H "Content-Type: application/json" --data-binary @- | jq -r ".id")

  printf '{
    "type": "NutsComm",
    "endpoint": "grpc://%s"
  }' "$2" | curl -s -X POST "$1/internal/didman/v1/did/$did/endpoint" -H "Content-Type: application/json" --data-binary @- > /dev/null

  echo "$did"
}

echo "------------------------------------"
echo "Cleaning up running Docker containers and volumes, and key material..."
echo "------------------------------------"

docker-compose down
docker-compose rm -f -v

echo "------------------------------------"
echo "Starting Docker containers..."
echo "------------------------------------"

docker-compose up -d

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

echo "" >> node-A/nuts.yaml
echo "  nodedid: $didNodeA" >> node-A/nuts.yaml
echo "" >> node-B/nuts.yaml
echo "  nodedid: $didNodeB" >> node-B/nuts.yaml