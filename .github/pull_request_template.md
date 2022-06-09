If this PR contains a new test, make sure
- [ ] it contains a `docker-compose.yml` file using the `nutsfoundation/nuts-node:master` image (for images that should be replaced during automated testing),
- [ ] it can be run with a `run-test.sh` script that is added to _all_ appropriate `run-tests.sh` scripts