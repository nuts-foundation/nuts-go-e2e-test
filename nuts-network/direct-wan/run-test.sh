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

echo "------------------------------------"
echo "Performing assertions..."
echo "------------------------------------"
# Wait for Nuts Network nodes to build connections
sleep 5
# Assert that node A is connected to B and vice versa using diagnostics. It should look something like this:
# [P2P Network] Connected peers #: 1
#	[P2P Network] Connected peers: (ID=172.19.0.2:43882,NodeID=urn:oid:1.3.6.1.4.1.54851.4:00000002,Addr=172.19.0.2:43882)
RESPONSE=$(curl -s http://localhost:11323/status/diagnostics)
if echo $RESPONSE | grep -q "connected_peers_count: 1"; then
  echo "Number of peers of node A is OK"
else
  echo "FAILED: Node A does not report 1 connected peer!" 1>&2
  echo $RESPONSE
  exit 1
fi
RESPONSE=$(curl -s http://localhost:21323/status/diagnostics)
if echo $RESPONSE | grep -q "connected_peers_count: 1"; then
  echo "Number of peers of node B is OK"
else
  echo "FAILED: Node B does not report 1 connected peer!" 1>&2
  echo $RESPONSE
  exit 1
fi

echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop
