#!/usr/bin/env bash

source ../../util.sh

echo "------------------------------------"
echo "Cleaning up running Docker containers and volumes, and key material..."
echo "------------------------------------"
docker-compose down
docker-compose rm -f -v
rm -rf ./node-data/*
rm -rf ./node-backup/*

echo "------------------------------------"
echo "Starting Docker containers..."
echo "------------------------------------"
docker-compose up -d
waitForDCService nodeA

echo "------------------------------------"
echo "Creating DID document and issuing VCs..."
echo "------------------------------------"
nodeDID=$(setupNode "http://localhost:11323" nodeA:5555)
createAuthCredential "http://localhost:11323" "$nodeDID" "$nodeDID"
vcID=$(createAuthCredential "http://localhost:11323" "$nodeDID" "$nodeDID")
revokeCredential "http://localhost:11323" "$vcID"
assertDiagnostics "http://localhost:11323" "transaction_count: 5"
assertDiagnostics "http://localhost:11323" "credential_count: 2"
assertDiagnostics "http://localhost:11323" "issued_credentials_count: 2"
assertDiagnostics "http://localhost:11323" "revocations_count: 1"

echo "------------------------------------"
echo "Making backups, then start with empty node..."
echo "------------------------------------"
sleep 1 # BBolt backup is made every second
echo "Making backups and removing node data"
docker compose stop
# Copy files not in BBolt DB, so they can be restored. Then empty data dir.
cp ./node-data/vcr/trusted_issuers.yaml ./node-backup/vcr/
cp -r ./node-data/crypto ./node-backup
rm -rf ./node-data/*
# Restart node, assert node data is empty
echo "Asserting node is empty"
BACKUP_INTERVAL=0 docker compose up -d
waitForDCService nodeA
assertDiagnostics "http://localhost:11323" "node_did: \"\""
assertDiagnostics "http://localhost:11323" "transaction_count: 0"
assertDiagnostics "http://localhost:11323" "credential_count: 0"
# Restore data and rebuild
echo "Restoring node data"
docker compose stop
rm -rf ./node-data/*
cp -r ./node-backup/* ./node-data/
BACKUP_INTERVAL=0 docker compose up -d
waitForDCService nodeA

echo "Rebuilding data"
docker compose exec nodeA nuts network reprocess "application/vc+json"
docker compose exec nodeA nuts network reprocess "application/ld+json;type=revocation"

# Wait for some time for reprocess to finish
sleep 5

assertDiagnostics "http://localhost:11323" "transaction_count: 5"
assertDiagnostics "http://localhost:11323" "credential_count: 2"
assertDiagnostics "http://localhost:11323" "issued_credentials_count: 2"
assertDiagnostics "http://localhost:11323" "revoked_credentials_count: 1"
assertDiagnostics "http://localhost:11323" "revocations_count: 1"