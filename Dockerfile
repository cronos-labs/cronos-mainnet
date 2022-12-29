FROM golang:1.18 as go_builder
WORKDIR /opt/app
ARG LATEST_VERSION
ARG OS_VERSION
RUN curl -L  https://github.com/crypto-org-chain/cronos/releases/download/v${LATEST_VERSION}/cronos_${LATEST_VERSION}_${OS_VERSION}.tar.gz > cronos_${LATEST_VERSION}-${OS_VERSION}.tar.gz
RUN mkdir cronos
RUN tar -xvzf cronos_${LATEST_VERSION}-${OS_VERSION}.tar.gz -C cronos

ENV PATH="${PATH}:/opt/app/cronos/bin"
CMD ["cronosd"]