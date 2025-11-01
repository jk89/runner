# YOLO Runner – Self-Hosted GitHub Actions Runner (DiD³ + Sysbox)

A **self-hosted GitHub Actions runner** supporting **DiD³** — Docker-in-Docker-in-Docker — powered by [Sysbox](https://github.com/nestybox/sysbox).

`docker pull 0x6a6f6e6e79/gha-runner-yolo:latest` [link](https://hub.docker.com/r/0x6a6f6e6e79/gha-runner-yolo)

Tested on Ubuntu 22.04

---

## Why Sysbox

Sysbox lets containers act like lightweight VMs:

- Enables **safe nested containers** (no `--privileged` required)  
- Provides full **PID, user, and mount namespaces**  
- **Mounts just work** — inner containers can bind and volume-mount cleanly  

---

## Install Sysbox (v0.6.6)

```bash
# 1. Stop and remove all containers
docker rm $(docker ps -a -q) -f

# 2. Download and install Sysbox v0.6.6
wget https://downloads.nestybox.com/sysbox/releases/v0.6.6/sysbox-ce_0.6.6-0.linux_amd64.deb
sudo apt-get install ./sysbox-ce_0.6.6-0.linux_amd64.deb -y

# 3. Restart Docker
sudo systemctl restart docker

# 4. Reconfigure the Sysbox package
sudo dpkg --configure -a

# 5. Verify installation
sysbox-runc --version
# expected: version: 0.6.6

docker info | grep Runtimes
# expected: sysbox-runc listed
```

## Example compose

```
version: '3.8'

services:
  gha-runner:
    build:
      context: .
      dockerfile: Dockerfile
    image: 0x6a6f6e6e79/gha-runner-yolo:latest
    runtime: sysbox-runc
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - runner-work:/home/runner/actions/_work
      - runner-tools:/home/runner/actions/_tools

volumes:
  runner-work:
  runner-tools:
```

## Example workflow

```
name: YOLO Runner Minimal Test

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  container-and-service:
    runs-on: [self-hosted, yolo]

    container:
      image: node:18
      options: --volume /var/run/docker.sock:/var/run/docker.sock

    services:
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Inside container
        run: |
          echo "🐳 Node version inside container:"
          node --version
          echo "📦 NPM version:"
          npm --version

      - name: Test Redis service
        run: |
          apt-get update && apt-get install -y redis-tools
          echo "💾 Pinging Redis..."
          redis-cli -h redis ping

      - name: Install Docker CLI
        run: |
          apt-get update && apt-get install -y docker.io

      - name: Run a nested container
        run: |
          echo "🚀 Running a container from the job container:"
          docker run --rm alpine:latest sh -c 'echo "Hello from D³!" && uname -a'

      - name: Prove DiD³ - Install Docker and build runner from within itself
        run: |
          echo "🎯 DiD³ PROOF: Installing Docker and building the runner from within a job running on that runner!"
          docker build -t gha-runner-inception:latest .
          docker images | grep inception
          echo "✅ Successfully built runner image from within the runner!"
```

# [Runner output](https://github.com/jk89/yolo-runner/actions/runs/18988465070/job/54236864804)