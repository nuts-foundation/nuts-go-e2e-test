#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!! Running test: OAuth flow       !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
./run-test.sh
