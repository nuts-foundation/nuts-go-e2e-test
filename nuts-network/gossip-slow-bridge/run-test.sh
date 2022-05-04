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
waitForDCService nodeC
waitForDCService nodeD
waitForDCService nodeE

# Wait for Nuts Network nodes to build connections
sleep 1

echo "------------------------------------"
echo "Creating root"
echo "------------------------------------"

# node-C gossips at a long interval and is the bridge between nodes A & B vs D & E
curl -s -X POST http://localhost:31323/internal/vdr/v1/did >/dev/null

sleep 60

# create 1000 new DID documents on each node
echo "------------------------------------"
echo "Creating transactions"
echo "------------------------------------"

START0=$(date +%s)
for i in {1..1000}
do
   curl -s -X POST http://localhost:11323/internal/vdr/v1/did >/dev/null
   curl -s -X POST http://localhost:21323/internal/vdr/v1/did >/dev/null
   curl -s -X POST http://localhost:41323/internal/vdr/v1/did >/dev/null
   curl -s -X POST http://localhost:51323/internal/vdr/v1/did >/dev/null
done

echo "------------------------------------"
echo "Performing assertions..."
echo "------------------------------------"

START1=$(date +%s)

waitForTXCount "NodeC" "http://localhost:31323/status/diagnostics" 4001 120
waitForTXCount "NodeA" "http://localhost:11323/status/diagnostics" 4001 120
waitForTXCount "NodeE" "http://localhost:51323/status/diagnostics" 4001 120

END=$(date +%s)
echo "Runtime with adding transactions: $((END - START0)) seconds"
echo "Runtime after adding transactions: $((END - $START1)) seconds"
echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop
