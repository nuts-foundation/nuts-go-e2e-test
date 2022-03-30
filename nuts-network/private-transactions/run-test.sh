#!/usr/bin/env bash

set -e

source ../../util.sh

function findNodeDID() {
  egrep -o 'nodedid:.*' $1 | awk '{print $2}'
}

function createAuthCredential() {
  printf '{
    "type": "NutsAuthorizationCredential",
    "issuer": "%s",
    "credentialSubject": {
      "id": "%s",
      "legalBase": {
        "consentType": "implied"
      },
      "resources": [],
      "purposeOfUse": "example",
      "subject": "urn:oid:2.16.840.1.113883.2.4.6.3:123456780"
    },
   "visibility": "private"
  }' "$2" "$3" | curl -s -X POST "$1/internal/vcr/v2/issuer/vc" -H "Content-Type: application/json" --data-binary @- > /dev/null
}

function searchAuthCredentials() {
  printf '{
    "query": {
      "@context": ["https://www.w3.org/2018/credentials/v1", "https://nuts.nl/credentials/v1"],
      "type": ["VerifiableCredential" ,"NutsAuthorizationCredential"],
      "credentialSubject": {
        "subject": "urn:oid:2.16.840.1.113883.2.4.6.3:123456780"
      }
    },
    "searchOptions": {
       "allowUntrustedIssuer": true
    }
  }' | curl -s -X POST "$1/internal/vcr/v2/search" -H "Content-Type: application/json" --data-binary @-
}

echo "------------------------------------"
echo "Starting Docker containers..."
echo "------------------------------------"
docker-compose up -d

waitForDCService nodeA
waitForDCService nodeB

# Wait for Nuts Network nodes to build connections
sleep 5

echo "------------------------------------"
echo "Asserting..."
echo "------------------------------------"

didNodeA=$(findNodeDID "node-A/nuts.yaml")
printf "NodeDID for node-a: %s\n" "$didNodeA"

didNodeB=$(findNodeDID "node-B/nuts.yaml")
printf "NodeDID for node-b: %s\n" "$didNodeB"

createAuthCredential "http://localhost:11323" "$didNodeA" "$didNodeB"
createAuthCredential "http://localhost:21323" "$didNodeB" "$didNodeA"

# Wait for transactions to sync
sleep 5

if [ $(searchAuthCredentials "http://localhost:11323" | jq "length") -ne 2 ]; then
  echo "failed to find NutsAuthorizationCredentials on Node-A"
  exit 1
fi

if [ $(searchAuthCredentials "http://localhost:21323" | jq "length") -ne 2 ]; then
  echo "failed to find NutsAuthorizationCredentials on Node-B"
  exit 1
fi

echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop
