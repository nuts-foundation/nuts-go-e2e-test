#!/usr/bin/env bash

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!! Running test suite: Nuts Network !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
pushd nuts-network || exit
./run-tests.sh
popd || exit

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!! Running test suite: OAuth flow   !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
pushd oauth-flow || exit
./run-tests.sh
popd || exit
