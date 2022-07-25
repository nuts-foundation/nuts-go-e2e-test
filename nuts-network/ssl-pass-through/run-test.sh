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
waitForDCService nodeA-backend
waitForDCService nodeB

echo "------------------------------------"
echo "Performing assertions (nodes are connected)..."
echo "------------------------------------"
# Wait for Nuts Network nodes to build connections
sleep 5
RESPONSE=$(curl -s http://localhost:11323/status/diagnostics)
if echo $RESPONSE | grep -q "connected_peers_count: 1"; then
  echo "Number of peers of node A is OK"
else
  echo "FAILED: Node A does not report 1 connected peer!" 1>&2
  echo $RESPONSE
  exitWithDockerLogs 1
fi
RESPONSE=$(curl -s http://localhost:21323/status/diagnostics)
if echo $RESPONSE | grep -q "connected_peers_count: 1"; then
  echo "Number of peers of node B is OK"
else
  echo "FAILED: Node B does not report 1 connected peer!" 1>&2
  echo $RESPONSE
  exitWithDockerLogs 1
fi


echo "------------------------------------"
echo "Creating transaction"
echo "------------------------------------"
curl -s -X POST http://localhost:11323/internal/vdr/v1/did >/dev/null
echo "------------------------------------"
echo "Performing assertions (number of transactions)..."
echo "------------------------------------"

waitForTXCount "NodeA" "http://localhost:11323/status/diagnostics" 1 10
waitForTXCount "NodeB" "http://localhost:21323/status/diagnostics" 1 10

echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop
