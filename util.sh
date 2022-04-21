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
    exit 1
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
    printf "FAILED: Service '%s' dit not get %d transaction within %d seconds" $SERVICE_NAME $TX_COUNT $TIMEOUT
    exit 1
  fi
  echo ""
}
