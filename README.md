This repository contains end-to-end tests for `nuts-go`.

# Prerequisites
To tun the tests you need the following tools:

- Docker
- docker-compose
- [jq](https://stedolan.github.io/jq/) for JSON operations
- [Earthly](https://earthly.dev) for reproducable builds (**optional**)

# Running tests
## On your machine

To run the tests execute `run-tests.sh`.

## Using Earthly

Make sure docker is installed and updated and [Install earthly](https://earthly.dev/get-earthly).
Then run the all tests:

```shell
earthly -P +all
```
