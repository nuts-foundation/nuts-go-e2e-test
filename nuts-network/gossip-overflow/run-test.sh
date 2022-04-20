#!/usr/bin/env bash

source ../../util.sh

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
sleep 1

# create 200 new DID documents on each node
echo "------------------------------------"
echo "Creating transactions"
echo "------------------------------------"

for i in {1..200}
do
   curl -s -X POST http://localhost:11323/internal/vdr/v1/did >/dev/null
done

echo "------------------------------------"
echo "Performing assertions..."
echo "------------------------------------"
sleep 15
# Assert that node B received all transactions
RESPONSE=$(curl -s http://localhost:21323/status/diagnostics)
if echo $RESPONSE | grep -q "transaction_count: 200"; then
  echo "Number of TXs of node B are OK"
else
  echo "FAILED: Node B does not report 200 TXs!" 1>&2
  echo $RESPONSE
  exit 1
fi

echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop
