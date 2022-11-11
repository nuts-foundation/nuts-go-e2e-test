#!/usr/bin/env bash

function waitForDCService {
  local SERVICE_NAME=$1
  printf "Waiting for docker compose service '%s' to become healthy" $SERVICE_NAME
  local retry=0
  local healthy=0
  while [ $retry -lt 30 ]; do
    local status=$(docker inspect -f {{.State.Health.Status}} $(docker compose ps -q $SERVICE_NAME))

    if [[ "$status" == "healthy" ]]; then
      healthy=1
      break
    fi

    printf "."
    sleep 0.5
    retry=$[$retry+1]
  done

  if [ $healthy -eq 0 ]; then
    echo "FAILED: Service took to long to start" 1>&2
    exitWithDockerLogs 1
  fi
  echo ""
}

function waitForTXCount {
  local SERVICE_NAME=$1
  local URL=$2
  local TX_COUNT=$3
  local TIMEOUT=$4
  printf "Waiting for service '%s' to contain %s transactions" $SERVICE_NAME $TX_COUNT
  local done=false
  local retry=0
  while [ $retry -lt $TIMEOUT ]; do

    local RESPONSE=$(curl -s $URL)
    if echo $RESPONSE | grep -q "transaction_count: $TX_COUNT"; then
      done=true
      break
    fi

    printf "."
    sleep 1
    retry=$[$retry+1]
  done

  if [ $done == false ]; then
    printf "FAILED: Service '%s' did not get %d transaction within %d seconds" $SERVICE_NAME $TX_COUNT $TIMEOUT 1>&2
    exitWithDockerLogs 1
  fi
  echo ""
}

function exitWithDockerLogs {
  local EXIT_CODE=$1
  docker compose logs
  docker compose stop
  exit $EXIT_CODE
}

# waitForKeyPress waits for the enter key to be pressed
function waitForKeyPress() {
  read -p "Press enter to continue"
}

# setupNode creates a node's DID document and registers its NutsComm endpoint.
# Args:     node HTTP address, node gRPC address
# Returns:  the created DID
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

# assertDiagnostic checks whether a certain string appears on a node's diagnostics page.
# Args: node HTTP address, string to assert
function assertDiagnostic() {
  local RESPONSE=$(curl -s "$1/status/diagnostics")
  if echo $RESPONSE | grep -q "${2}"; then
    echo "Diagnostics contains '${2}'"
  else
    echo "FAILED: diagnostics does not report '${2}'" 1>&2
    echo $RESPONSE 1>&2
    exitWithDockerLogs 1
  fi
}

# readDiagnostic reads a specific value from the node's diagnostics page.
# Args: node HTTP address, key to read
function readDiagnostic() {
  # Given 'uptime'; read diagnostics, find line with 'uptime: ' and remove key + colon, print with stripped spaces
  local result=$(curl -s "$1/status/diagnostics" | grep "${2}:" | sed -e "s/$2://")
  echo -n "${result//[[:space:]]/}"  # builtin sh on mac does not accept -n option, just prints it instead
}

# createAuthCredential issues a NutsAuthorizationCredential
# Args:     issuing node HTTP address, issuer DID, subject DID
# Returns:  the VC ID
function createAuthCredential() {
  printf '{
    "type": "NutsAuthorizationCredential",
    "issuer": "%s",
    "credentialSubject": {
      "id": "%s",
      "resources": [],
      "purposeOfUse": "example",
      "subject": "urn:oid:2.16.840.1.113883.2.4.6.3:123456780"
    },
   "visibility": "private"
  }' "$2" "$3" | curl -s -X POST "$1/internal/vcr/v2/issuer/vc" -H "Content-Type: application/json" --data-binary @- | jq ".id" | sed "s/\"//g"
}

# readCredential resolves a VC
# Args:     node HTTP address, VC ID
# Returns:  the VC as JSON
function readCredential() {
  curl -s "$1/internal/vcr/v2/vc/${2//#/%23}"
}

# revokeCredential revokes a VC
# Args: node HTTP address, VC ID
function revokeCredential() {
  curl -s -X DELETE "$1/internal/vcr/v2/issuer/vc/${2//#/%23}"
}

# runOnAlpine runs the given command on a Alpine docker image
# Args: Docker volume mount (hostPath:dockerPath), remaining args are the command to run
function runOnAlpine() {
  # Say you have a folder './data/' that is used by the Nuts node, and you want to delete its contents.
  # Running 'rm -rf ./data/*' from the run-test.sh script will fail with permission issues.
  # This is due to github actions file permission issues explained in https://github.com/actions/runner/issues/691
  #
  # You can successfully delete the entire folder using:
  # runOnAlpine "$(pwd):/host/" rm -rf /host/data
  docker run --rm -v "$1" alpine "${@:2}"
}