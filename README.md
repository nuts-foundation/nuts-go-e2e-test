This repository contains end-to-end tests for the [nuts-node](https://github.com/nuts-foundation/nuts-node).

# Writing tests
## Automated testing
[Automated testing](https://github.com/nuts-foundation/nuts-node/blob/master/.github/workflows/e2e-tests.yaml) of the nuts-node relies on some find and replace magic for which the following requirements must be met:

- Each test has a `docker-compose.yml` and a `run-test.sh` file. 
- References to Docker image `nutsfoundation/nuts-node:master` in the `docker-compose.yml` file are automatically replaced with the image that is built in the automated test.
- The `run-test.sh` of each test should be added to the respective group's `/<test-group>/run-tests.sh` script.
- All `/<test-group>/run-tests.sh` should be added to `/run-tests.sh`

# Running tests
## Prerequisites
To tun the tests you need the following tools:

- Docker
- [jq](https://stedolan.github.io/jq/) for JSON operations

## On your machine

To run the tests execute `run-tests.sh`.
