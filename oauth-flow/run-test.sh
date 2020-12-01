#!/usr/bin/env bash
source ../util.sh

echo "------------------------------------"
echo "Cleaning up running Docker containers and volumes, and key material..."
echo "------------------------------------"
docker-compose down
docker-compose rm -f -v
rm -rf ./node-*/data
rm -rf ./common/data
mkdir -p ./node-A/data/keys
mkdir -p ./node-B/data/keys
touch ./node-A/data/keys/truststore.pem

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
docker-compose exec -e NUTS_MODE=cli nodeA-backend nuts crypto selfsign-vendor-cert "Vendor A" /opt/nuts/keys/vendor_certificate.pem
docker-compose exec -e NUTS_MODE=cli nodeA-backend nuts registry register-vendor /opt/nuts/keys/vendor_certificate.pem

# Register Vendor B
docker-compose exec -e NUTS_MODE=cli nodeB nuts crypto selfsign-vendor-cert "Vendor B" /opt/nuts/keys/vendor_certificate.pem
docker-compose exec -e NUTS_MODE=cli nodeB nuts registry register-vendor /opt/nuts/keys/vendor_certificate.pem

# Since node B connects to A's gRPC server, so A needs to trust B's Vendor CA certificate since it's used to issue the client certificate
docker cp ./node-B/data/keys/vendor_certificate.pem $(docker-compose ps -q nodeA):/etc/nginx/ssl/truststore.pem
# This also means that B must trust A's server certificate (by trusting our custom Root CA)
docker cp ../keys/ca-certificate.pem $(docker-compose ps -q nodeB):/usr/local/share/ca-certificates/rootca.crt
docker-compose exec nodeB update-ca-certificates

docker-compose restart

echo "------------------------------------"
echo "Waiting for services to restart..."
echo "------------------------------------"
waitForDCService nodeA-backend
waitForDCService nodeB

echo "------------------------------------"
echo "Registering care organizations..."
echo "Registering endpoints..."
echo "------------------------------------"

docker-compose exec -e NUTS_MODE=cli nodeA-backend nuts registry vendor-claim urn:oid:2.16.840.1.113883.2.4.6.1:A "Org A"
docker-compose exec -e NUTS_MODE=cli nodeB nuts registry vendor-claim urn:oid:2.16.840.1.113883.2.4.6.1:B "Org B"
docker-compose exec -e NUTS_MODE=cli nodeA-backend nuts registry register-endpoint urn:oid:2.16.840.1.113883.2.4.6.1:A oauth "https://nodeA:443/auth/accesstoken"

# Wait for Nuts Network nodes to build connections
sleep 5

echo "------------------------------------"
echo "Obtain client certificate..."
echo "------------------------------------"
# Generate TLS keys for node-B
openssl ecparam -name prime256v1 -genkey -noout -out ./node-B/data/keys/tls-privatekey.pem
openssl ec -in ./node-B/data/keys/tls-privatekey.pem -pubout -out ./node-B/data/keys/tls-publickey.pem

# Get a client certificate from B
curl -X POST -s --data-binary "@./node-B/data/keys/tls-publickey.pem" http://localhost:21323/crypto/certificate/tls > ./node-B/data/keys/tls-certificate.pem
if grep -q "BEGIN CERTIFICATE" ./node-B/data/keys/tls-certificate.pem; then
  echo "TLS client certificate stored in ./node-B/data/keys/tls-certificate.pem"
else
  echo "FAILED: Could not get TLS client certificate from node-B" 1>&2
  cat ./node-B/data/keys/tls-certificate.pem
  exit 1
fi

echo "------------------------------------"
echo "Sign contract..."
echo "------------------------------------"
# draw up a contract
RESPONSE=$(curl -X PUT -s --data-binary "@./node-B/drawupcontractrequest.json" http://localhost:21323/internal/auth/experimental/contract/drawup -H "Content-Type:application/json")
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
sed "s/BASE64_VP/$(cat ./node-B/data/vp.txt)/" ./node-B/jwtbearertokentemplate.json > ./node-B/data/jwtbearertoken.json
RESPONSE=$(curl -X POST -s --data-binary "@./node-B/data/jwtbearertoken.json" http://localhost:21323/auth/jwtbearertoken -H "Content-Type:application/json")
if echo $RESPONSE | grep -q "bearer_token"; then
  echo $RESPONSE | sed -E 's/.*"bearer_token":"([^"]*).*/\1/' > ./node-B/data/bearertoken.txt
  echo "bearer token stored in ./node-B/data/bearertoken.txt"
else
  echo "FAILED: Could not get JWT bearer token from node-B" 1>&2
  echo $RESPONSE
  exit 1
fi

# Offer bearer token to Node A
# sed "s/BASE64_BT/$(cat ./node-B/data/bearertoken.txt)/" ./node-B/accesstokentemplate.json > ./node-B/data/accesstoken.json
RESPONSE=$(docker-compose exec nodeB curl -X POST -s -F "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" -F "assertion=$(cat ./node-B/data/bearertoken.txt)" --cert /opt/nuts/keys/tls-certificate.pem --key /opt/nuts/keys/tls-privatekey.pem https://nodeA:443/auth/accesstoken)
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

RESPONSE=$(docker-compose exec nodeB curl --cert /opt/nuts/keys/tls-certificate.pem --key /opt/nuts/keys/tls-privatekey.pem https://nodeA:443/ping -H "Authorization: bearer $(cat ./node-B/data/accesstoken.txt)" -v)
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