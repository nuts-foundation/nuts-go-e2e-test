FROM earthly/dind:ubuntu

COPY . /tests

RUN apt-get update && \
    apt-get install -y jq

nuts-node:
    COPY /nuts-node/ /nuts-node/
    WORKDIR /nuts-node

    RUN ls -lisah .

    FROM DOCKERFILE .

    SAVE IMAGE nuts-node

network-direct-wan:
    WORKDIR /tests/nuts-network/direct-wan

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

network-ssloffloading:
    WORKDIR /tests/nuts-network/ssl-offloading

    # currently disabled
    RUN exit 0

network-ssl-pass-through:
    WORKDIR /tests/nuts-network/ssl-pass-through

    # currently disabled
    RUN exit 0

oauth-flow:
    WORKDIR /tests/oauth-flow

    # Disable TTY allocation (if we don't `docker-compose exec` won't work)
    RUN sed -i "s/docker-compose exec/docker-compose exec -T/g" ./run-test.sh

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

all:
    BUILD +network-direct-wan
    BUILD +network-ssloffloading
    BUILD +network-ssl-pass-through
    BUILD +oauth-flow
