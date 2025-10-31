# Stage 1: Build the modified runner
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:6.0 AS builder

WORKDIR /build

# Copy your modified source
COPY . .

# Build and package
RUN chmod +x ./src/dev.sh && \
    cd src && \
    ./dev.sh layout && \
    ./dev.sh package

# Stage 2: Runtime image
FROM --platform=$TARGETPLATFORM ubuntu:22.04

ARG TARGETARCH
ARG OS=linux

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies including Docker
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    sudo \
    git \
    jq \
    ca-certificates \
    gnupg \
    lsb-release && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -G sudo,docker -ms /bin/bash runner && \
    install -o runner -g runner -m 0755 -d /home/runner/actions && \
    echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner

USER runner
WORKDIR /home/runner/actions

# Copy built runner (it's at /build/_layout after running from src/)
COPY --from=builder /build/_layout .

COPY start.sh ./start.sh

USER root

RUN ./bin/installdependencies.sh && \
    chmod +x ./start.sh && \
    chown runner:runner ./start.sh

USER runner

CMD ["./start.sh"]