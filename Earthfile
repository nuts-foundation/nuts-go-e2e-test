VERSION 0.6
FROM earthly/dind:ubuntu

COPY . /tests

RUN apt-get update && \
    apt-get install -y jq

network-direct-wan:
    WORKDIR /tests/nuts-network/direct-wan

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

private-transactions-prepare:
    WORKDIR /tests/nuts-network/private-transactions

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./prepare.sh
    END

private-transactions:
    FROM +private-transactions-prepare
    WORKDIR /tests/nuts-network/private-transactions

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

network-ssl-offloading:
    WORKDIR /tests/nuts-network/ssl-offloading

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

network-ssl-pass-through:
    WORKDIR /tests/nuts-network/ssl-pass-through

    # currently disabled
    RUN exit 0

network-gossip:
    WORKDIR /tests/nuts-network/gossip

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

network-gossip-overflow:
    WORKDIR /tests/nuts-network/gossip-overflow

    WITH DOCKER \
        --compose docker-compose.yml
        RUN ./run-test.sh
    END

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
    BUILD +network-ssl-offloading
    BUILD +network-ssl-pass-through
    BUILD +oauth-flow
    BUILD +private-transactions
    BUILD +network-gossip
    BUILD +network-gossip-overflow
