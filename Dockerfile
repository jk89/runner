# Stage 1: Builder
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:6.0 AS builder
WORKDIR /build
COPY . .

RUN chmod +x ./src/dev.sh && cd src && ./dev.sh layout && ./dev.sh package

# Stage 2: Runtime
FROM --platform=$TARGETPLATFORM ubuntu:22.04 AS runtime

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies including Docker (pinned for Sysbox compatibility)
# docker-ce 28.5.1 and containerd.io 1.7.28 - containerd 1.7.29+ breaks Sysbox
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget sudo git jq ca-certificates gnupg lsb-release apt-transport-https gnupg2 \
    iproute2 procps lsof util-linux gpg openssh-client \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
    docker-ce=5:28.5.1-1~ubuntu.22.04~jammy \
    docker-ce-cli=5:28.5.1-1~ubuntu.22.04~jammy \
    docker-buildx \
    containerd.io=1.7.28-1~ubuntu.22.04~jammy \
    docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# Create non-root runner user and required dirs
RUN useradd -m -s /bin/bash runner \
 && mkdir -p /home/runner/actions /home/runner/actions/_work /home/runner/actions/_tools /home/runner/logs \
 && chown -R runner:runner /home/runner \
 # allow runner to run as sudo without password
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner

# Add docker group and link runner to it
RUN groupadd -g 999 docker || true \
 && usermod -aG docker runner

# Copy built runner layout from builder
COPY --from=builder /build/_layout /home/runner/actions

# Copy start script; ensure executable
COPY start.sh /home/runner/actions/start.sh
RUN chmod +x /home/runner/actions/start.sh

# Install missing ICU library for Ubuntu 22.04 but error is for 71
#RUN apt-get update && apt-get install -y --no-install-recommends libicu70

# Run any installer as root (installs runner deps), then drop to non-root
RUN if [ -x /home/runner/actions/bin/installdependencies.sh ]; then /home/runner/actions/bin/installdependencies.sh; fi \
 && chown -R runner:runner /home/runner/actions

USER runner
WORKDIR /home/runner/actions

CMD ["./start.sh"]
