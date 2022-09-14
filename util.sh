#!/usr/bin/env bash

function waitForDCService {
  SERVICE_NAME=$1
  printf "Waiting for docker-compose service '%s' to become healthy" $SERVICE_NAME
  retry=0
  healthy=0
  while [ $retry -lt 30 ]; do
    status=$(docker inspect -f {{.State.Health.Status}} $(docker-compose ps -q $SERVICE_NAME))

    if [[ "$status" == "healthy" ]]; then
      healthy=1
      break
    fi

    printf "."
    sleep 0.5
    retry=$[$retry+1]
  done

  if [ $healthy -eq 0 ]; then
    echo "FAILED: Service took to long to start"
    exitWithDockerLogs 1
  fi
  echo ""
}

function waitForTXCount {
  SERVICE_NAME=$1
  URL=$2
  TX_COUNT=$3
  TIMEOUT=$4
  printf "Waiting for service '%s' to contain %s transactions" $SERVICE_NAME $TX_COUNT
  done=false
  retry=0
  while [ $retry -lt $TIMEOUT ]; do

    RESPONSE=$(curl -s $URL)
    if echo $RESPONSE | grep -q "transaction_count: $TX_COUNT"; then
      done=true
      break
    fi

    printf "."
    sleep 1
    retry=$[$retry+1]
  done

  if [ $done == false ]; then
    printf "FAILED: Service '%s' did not get %d transaction within %d seconds" $SERVICE_NAME $TX_COUNT $TIMEOUT
    exitWithDockerLogs 1
  fi
  echo ""
}

function exitWithDockerLogs {
  EXIT_CODE=$1
  docker-compose logs
  docker-compose stop
  exit $EXIT_CODE
}

# waitForKeyPress waits for the enter key to be pressed
function waitForKeyPress() {
  read -p "Press enter to continue"
}

# setupNode creates a node's DID document and registers its NutsComm endpoint.
# Args: node HTTP address, node gRPC address
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

# assertDiagnostics checks whether a certain string appears on a node's diagnostics page.
# Args: node HTTP address, string to assert
function assertDiagnostics() {
  RESPONSE=$(curl -s "$1/status/diagnostics")
  if echo $RESPONSE | grep -q "${2}"; then
    echo "Diagnostics contains '${2}'"
  else
    echo "FAILED: diagnostics does not report '${2}'" 1>&2
    echo $RESPONSE
    exitWithDockerLogs 1
  fi
}

# createAuthCredential issues a NutsAuthorizationCredential
# Args: issuing node HTTP address, issuer DID, subject DID
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
  }' "$2" "$3" | curl -s -X POST "$1/internal/vcr/v2/issuer/vc" -H "Content-Type: application/json" --data-binary @- | jq ".id" | sed "s/\"//g"
}

# revokeCredential revokes a VC
# Args: node HTTP address, VC ID
function revokeCredential() {
  curl -s -X DELETE "$1/internal/vcr/v2/issuer/vc/${2//#/%23}"
}