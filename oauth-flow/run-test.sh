#!/usr/bin/env bash
source ../util.sh

echo "------------------------------------"
echo "Cleaning up running Docker containers and volumes, and key material..."
echo "------------------------------------"
docker-compose down
docker-compose rm -f -v
rm -rf ./node-*/data

echo "------------------------------------"
echo "Starting Docker containers..."
echo "------------------------------------"
docker-compose up -d
waitForDCService nodeA-backend
waitForDCService nodeB

echo "------------------------------------"
echo "Registering vendors..."
echo "------------------------------------"
# Register Vendor A
VENDOR_A_DIDDOC=$(docker-compose exec nodeA-backend nuts vdr create-did)
VENDOR_A_DID=$(echo $VENDOR_A_DIDDOC | jq -r .id)
echo Vendor A DID: $VENDOR_A_DID
# Add endpoint
VENDOR_A_DIDDOC=$(echo $VENDOR_A_DIDDOC | jq ". |= . + {service: [{id:\"${VENDOR_A_DID}#oauth\",type:\"oauth\",serviceEndpoint:\"https://nodeA:443/auth/accesstoken\"}]}")
# Add assertionMethod
VENDOR_A_KEYID=$(echo $VENDOR_A_DIDDOC | jq -r '.verificationMethod[0].id')
VENDOR_A_DIDDOC=$(echo $VENDOR_A_DIDDOC | jq ". |= . + {assertionMethod: [\"${VENDOR_A_KEYID}\"]}")
# Perform update
echo $VENDOR_A_DIDDOC > ./node-A/data/updated-did.json
DIDDOC_HASH=$(docker-compose exec nodeA-backend nuts vdr resolve $VENDOR_A_DID --metadata | jq -r .hash)
docker-compose exec nodeA-backend nuts vdr update "${VENDOR_A_DID}" "${DIDDOC_HASH}" /opt/nuts/data/updated-did.json

# Register Vendor B
VENDOR_B_DIDDOC=$(docker-compose exec nodeB nuts vdr create-did)
VENDOR_B_DID=$(echo $VENDOR_B_DIDDOC | jq -r .id)
echo Vendor B DID: $VENDOR_B_DID
# Add assertionMethod
VENDOR_B_KEYID=$(echo $VENDOR_B_DIDDOC | jq -r '.verificationMethod[0].id')
VENDOR_B_DIDDOC=$(echo $VENDOR_B_DIDDOC | jq ". |= . + {assertionMethod: [\"${VENDOR_B_KEYID}\"]}")
# Perform update
echo $VENDOR_B_DIDDOC > ./node-B/data/updated-did.json
DIDDOC_HASH=$(docker-compose exec nodeB nuts vdr resolve $VENDOR_B_DID --metadata | jq -r .hash)
docker-compose exec nodeB nuts vdr update "${VENDOR_B_DID}" "${DIDDOC_HASH}" /opt/nuts/data/updated-did.json

echo Waiting 2 seconds for updates to be propagated on the network...
sleep 2

echo "------------------------------------"
echo "Sign contract..."
echo "------------------------------------"

# draw up a contract
REQUEST="{\"type\": \"PractitionerLogin\",\"language\": \"EN\",\"version\": \"v3\",\"legalEntity\": \"${VENDOR_B_DID}\"}"
RESPONSE=$(echo $REQUEST | curl -X PUT --data-binary @- http://localhost:21323/internal/auth/experimental/contract/drawup -H "Content-Type:application/json")
if echo $RESPONSE | grep -q "PractitionerLogin"; then
  echo $RESPONSE | sed -E 's/.*"message":"([^"]*).*/\1/' > ./node-B/data/contract.txt
  echo "Contract stored in ./node-B/data/contract.txt"
else
  echo "FAILED: Could not get contract drawn up at node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# sign the contract with dummy means
sed "s/BASE64_CONTRACT/$(cat ./node-B/data/contract.txt)/" ./node-B/createsigningsessionrequesttemplate.json > ./node-B/data/createsigningsessionrequest.json
RESPONSE=$(curl -X POST -s --data-binary "@./node-B/data/createsigningsessionrequest.json" http://localhost:21323/internal/auth/experimental/signature/session -H "Content-Type:application/json")
if echo $RESPONSE | grep -q "sessionPtr"; then
  SESSION=$(echo $RESPONSE | sed -E 's/.*"sessionID":"([^"]*).*/\1/')
  echo $SESSION
else
  echo "FAILED: Could not get contract signed at node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# poll once for status created
RESPONSE=$(curl "http://localhost:21323/internal/auth/experimental/signature/session/$SESSION")
if echo $RESPONSE | grep -q "created"; then
  echo $RESPONSE
else
  echo "FAILED: Could not get session status from node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# poll twice for status success
RESPONSE=$(curl "http://localhost:21323/internal/auth/experimental/signature/session/$SESSION")
if echo $RESPONSE | grep -q "in-progress"; then
  echo $RESPONSE
else
  echo "FAILED: Could not get session status from node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# poll three times for status completed
RESPONSE=$(curl "http://localhost:21323/internal/auth/experimental/signature/session/$SESSION")
if echo $RESPONSE | grep -q "completed"; then
  echo $RESPONSE | sed -E 's/.*"verifiablePresentation":(.*\]}).*/\1/' | base64 > ./node-B/data/vp.txt
  echo "VP stored in ./node-B/data/vp.txt"
else
  echo "FAILED: Could not get session status from node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

echo "------------------------------------"
echo "Perform OAuth 2.0 flow..."
echo "------------------------------------"
# Create JWT bearer token
VP=$(cat ./node-B/data/vp.txt)
REQUEST="{\"custodian\":\"${VENDOR_A_DID}\",\"actor\":\"${VENDOR_B_DID}\",\"identity\":\"${VP}\",\"scope\":\"nuts\"}"
RESPONSE=$(echo $REQUEST | curl -X POST -s --data-binary @- http://localhost:21323/auth/jwtbearertoken -H "Content-Type:application/json")
echo $RESPONSE
if echo $RESPONSE | grep -q "bearer_token"; then
  echo $RESPONSE | sed -E 's/.*"bearer_token":"([^"]*).*/\1/' > ./node-B/data/bearertoken.txt
  echo "bearer token stored in ./node-B/data/bearertoken.txt"
else
  echo "FAILED: Could not get JWT bearer token from node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# Offer bearer token to Node A
RESPONSE=$(docker-compose exec nodeB curl -X POST --insecure -s -F "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" -F "assertion=$(cat ./node-B/data/bearertoken.txt)" --cert /opt/nuts/certificate-and-key.pem --key /opt/nuts/certificate-and-key.pem https://nodeA:443/auth/accesstoken)
if echo $RESPONSE | grep -q "access_token"; then
  echo $RESPONSE | sed -E 's/.*"access_token":"([^"]*).*/\1/' > ./node-B/data/accesstoken.txt
  echo "access token stored in ./node-B/data/accesstoken.txt"
else
  echo "FAILED: Could not get JWT access token from node-A" 1>&2
  echo $RESPONSE
  exit 1
fi

echo "------------------------------------"
echo "Retrieving data..."
echo "------------------------------------"

RESPONSE=$(docker-compose exec nodeB curl --insecure --cert /opt/nuts/certificate-and-key.pem --key /opt/nuts/certificate-and-key.pem https://nodeA:443/ping -H "Authorization: bearer $(cat ./node-B/data/accesstoken.txt)" -v)
if echo $RESPONSE | grep -q "pong"; then
  echo "success!"
else
  echo "FAILED: Could not ping node-A" 1>&2
  echo $RESPONSE
  exit 1
fi

echo "------------------------------------"
echo "Stopping Docker containers..."
echo "------------------------------------"
docker-compose stop