# YOLO Runner – Self-Hosted GitHub Actions Runner (DiD³ + Sysbox)

A **self-hosted GitHub Actions runner** supporting **DiD³** — Docker-in-Docker-in-Docker — powered by [Sysbox](https://github.com/nestybox/sysbox).

`docker pull 0x6a6f6e6e79/gha-runner-yolo:latest` [link](https://hub.docker.com/r/0x6a6f6e6e79/gha-runner-yolo)

Tested on Ubuntu 22.04

---

## What is DiD³?

**Three layers of Docker isolation:**

1. **D¹**: Host machine running Docker with Sysbox
2. **D²**: Runner container with isolated dockerd
3. **D³**: Job containers can run `docker build`, `docker run`, etc.

## Why Sysbox

Sysbox lets containers act like lightweight VMs:

- Enables **safe nested containers** (no `--privileged` required)  
- Provides full **PID, user, and mount namespaces**  
- **Mounts just work** — inner containers can bind and volume-mount cleanly  
- **Security**: Root in container ≠ root on host

---

## Security Comparison

### ❌ Typical Setup (INSECURE):
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock  # Root access to host!
```
**Problem**: Malicious workflow can escape and compromise entire host.

### ✅ YOLO Runner (SECURE):
```yaml
runtime: sysbox-runc  # Isolated dockerd per runner
```
**Benefit**: Each runner has isolated Docker daemon. Container escape only affects that runner.

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

## GitHub Token Setup

### Creating a Personal Access Token

1. Go to [GitHub Settings → Developer Settings → Personal Access Tokens → Tokens (classic)](https://github.com/settings/tokens)
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Name it: `YOLO Runner - myrepo` (or your org name)
4. Set expiration
5. Select the appropriate scope:
   - **Repository-level runner**: ✅ `repo` (full control of private repositories)
   - **Organisation-level runner**: ✅ `admin:org` (full control of orgs and teams)
6. Click **"Generate token"** at the bottom
7. **⚠️ Copy the token immediately** - it won't be shown again!
8. Paste into your `.env` file as `ACCESS_TOKEN=ghp_...`

### Token Scopes Summary

| Runner Type | Token Scope | Repository Format |
|-------------|-------------|-------------------|
| **Repository-level** | `repo` | `username/repo` or `orgname/repo` |
| **Organisation-level** | `admin:org` | `orgname` only |

### Security Recommendation for Organisations

For production org-level runners, **create a dedicated bot account**:
1. Create a new GitHub account (e.g., `myorg-runner-bot`)
2. Add it to your organisation with appropriate permissions
3. Generate the token from this bot account
4. **Benefit**: Token compromise doesn't expose your personal account - only the bot's limited permissions are at risk

---

## Configuration

### Environment Variables

The runner is configured via a `.env` file. See [`.env.example`](.env.example) for full configuration options.

**Required variables:**
- `REPOSITORY` - Repository (`username/repo` or `orgname/repo`) or Organisation (`orgname`) to register runner with
- `ACCESS_TOKEN` - GitHub Personal Access Token (see [Token Setup](#github-token-setup) above)

**Optional variables:**
- `RUNNER_NAME` - Prefix for runner names (default: `yolo-runner`)
  - Final name format: `{RUNNER_NAME}-{container-hostname}`
  - Example: `yolo-runner-a1b2c3d4e5f6`
- `RUNNER_LABELS` - Comma-separated labels for targeting in workflows (default: `self-hosted,linux,docker,yolo`)

---

## Quick Start

### 1. Create `.env` file:

**Repository-level runner** (`.env`):
```bash
REPOSITORY=username/myrepo  # or orgname/myrepo
ACCESS_TOKEN=ghp_xxxxx
RUNNER_NAME=yolo-repo-runner
RUNNER_LABELS=self-hosted,linux,docker,yolo,repo
```

**Organisation-level runner** (`.env`):
```bash
REPOSITORY=orgname
ACCESS_TOKEN=ghp_xxxxx
RUNNER_NAME=yolo-org-runner
RUNNER_LABELS=self-hosted,linux,docker,yolo,org
```

### 2. Create `docker-compose.yml`: 
```yaml
version: '3.8'

services:
  gha-runner-yolo:
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

### 3. Start runners:
```bash
docker-compose up -d

# Or scale to multiple runners:
docker-compose up -d --scale gha-runner-yolo=10
```

### 4. Create a workflow:

See [`.github/workflows/test-yolo-runner.yml`](.github/workflows/test-yolo-runner.yml) for a complete example, or [view the live runner output](https://github.com/jk89/yolo-runner/actions/runs/18988465070/job/54236864804).
```yaml
name: YOLO Runner Test

on: [push, workflow_dispatch]

jobs:
  test:
    runs-on: [self-hosted, yolo]

    container:
      image: node:18

    services:
      redis:
        image: redis:7

    steps:
      - uses: actions/checkout@v4
      
      - name: Test job container
        run: node --version
      
      - name: Test service container
        run: |
          apt-get update && apt-get install -y redis-tools
          redis-cli -h redis ping
      
      - name: Test DiD³ - Docker-in-Docker-in-Docker
        run: |
          apt-get install -y docker.io
          docker run --rm alpine echo "Hello from D³!"
```

---

## Multi-Tier Setup

For production workloads, run separate pools for different performance tiers.

**High-performance runners** (`.env.highperf`):
```bash
REPOSITORY=orgname
ACCESS_TOKEN=ghp_xxxxx
RUNNER_NAME=yolo-runner-highperf
RUNNER_LABELS=self-hosted,linux,docker,yolo,highperf
```

**Standard runners** (`.env.standard`):
```bash
REPOSITORY=orgname
ACCESS_TOKEN=ghp_xxxxx
RUNNER_NAME=yolo-runner-standard
RUNNER_LABELS=self-hosted,linux,docker,yolo,standard
```

**High-performance compose** (`docker-compose.highperf.yml`):
```yaml
version: '3.8'

services:
  gha-runner-yolo:
    image: 0x6a6f6e6e79/gha-runner-yolo:latest
    runtime: sysbox-runc
    restart: unless-stopped
    env_file:
      - .env.highperf
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G
    volumes:
      - runner-work-highperf:/home/runner/actions/_work
      - runner-tools-highperf:/home/runner/actions/_tools

volumes:
  runner-work-highperf:
  runner-tools-highperf:
```

**Standard compose** (`docker-compose.standard.yml`):
```yaml
version: '3.8'

services:
  gha-runner-yolo:
    image: 0x6a6f6e6e79/gha-runner-yolo:latest
    runtime: sysbox-runc
    restart: unless-stopped
    env_file:
      - .env.standard
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
    volumes:
      - runner-work-standard:/home/runner/actions/_work
      - runner-tools-standard:/home/runner/actions/_tools

volumes:
  runner-work-standard:
  runner-tools-standard:
```

Start different tiers:
```bash
# 10 high-performance runners
docker-compose -f docker-compose.highperf.yml up -d --scale gha-runner-yolo=10

# 40 standard runners
docker-compose -f docker-compose.standard.yml up -d --scale gha-runner-yolo=40
```

Target specific tiers in workflows:
```yaml
jobs:
  heavy-build:
    runs-on: [self-hosted, highperf]
    steps:
      - run: echo "Running on powerful hardware"
  
  light-test:
    runs-on: [self-hosted, standard]
    steps:
      - run: echo "Running on standard hardware"
```