#!/usr/bin/env bash
source ../util.sh

# Shut down existing containers
docker compose stop
docker compose rm -f -v
rm -rf ./data
mkdir ./data

# Start new stack
docker compose pull
docker compose up -d

waitForDCService node
waitForDCService ehr
waitForDCService admin

go test -v .