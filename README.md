This repository contains end-to-end tests for the [nuts-node](https://github.com/nuts-foundation/nuts-node).

# Writing tests
## Automated testing
[Automated testing](https://github.com/nuts-foundation/nuts-node/blob/master/.github/workflows/e2e-tests.yaml) of the nuts-node relies on some find and replace magic for which the following requirements must be met:

- Each test has a `+target` under `all`  in the `Earthfile`
- Tests in the `Earthfile` should contain `WITH DOCKER` so the correct Docker image can be inserted.
- Each test has a `docker-compose.yml` and a `run-test.sh` file. 
- References to Docker image `nutsfoundation/nuts-node:master` in the `docker-compose.yml` file are automatically replaced with the image that is built in the automated test.

## Local testing
For local testing without earthly:
- The `run-test.sh` of each test should be added to the respective group's `/<test-group>/run-tests.sh` script.
- All `/<test-group>/run-tests.sh` should be added to `/run-tests.sh`

# Running tests
## Prerequisites
To tun the tests you need the following tools:

- Docker
- docker-compose
- [jq](https://stedolan.github.io/jq/) for JSON operations
- [Earthly](https://earthly.dev) for reproducable builds (**optional**)

## On your machine

To run the tests execute `run-tests.sh`.

## Using Earthly

Make sure docker is installed and updated and [Install earthly](https://earthly.dev/get-earthly).
Then run the all tests:

```shell
earthly -P +all
```
