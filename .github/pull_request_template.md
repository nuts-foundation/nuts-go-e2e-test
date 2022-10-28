If this PR contains a new test, make sure
- [ ] it contains a `docker-compose.yml` file using the `${IMAGE_NODE_A:-nutsfoundation/nuts-node:master}` (and `B` for the second node) image. 
  This only applied to images that should be replaced during automated testing),
- [ ] it can be run with a `run-test.sh` script that is called from _all_ appropriate `run-tests.sh` scripts