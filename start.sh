#!/bin/bash
set -e

cd /home/runner/actions

# Function to get registration token
get_token() {
    # Determine if org or repo level
    if [[ "$REPOSITORY" != *"/"* ]]; then
        # Organization-level runner
        API_PATH="orgs/${REPOSITORY}"
    else
        # Repository-level runner
        API_PATH="repos/${REPOSITORY}"
    fi

    echo "🔑 Requesting token from ${API_PATH}..." >&2

    local token=$(curl -fsS -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/${API_PATH}/actions/runners/registration-token \
        | jq -r '.token // empty')
    
    if [ -z "$token" ]; then
        echo "❌ Failed to get registration token" >&2
        echo "  Check: ACCESS_TOKEN has correct scope" >&2
        echo "  Org runner needs: admin:org" >&2
        echo "  Repo runner needs: repo" >&2
        return 1
    fi
    
    echo "$token"
}

# Validate environment
if [ -z "$REPOSITORY" ]; then
    echo "❌ REPOSITORY not set"
    echo "  Set to: 'myorg' (org-level) or 'myorg/myrepo' (repo-level)"
    exit 1
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ ACCESS_TOKEN not set"
    exit 1
fi

echo "🚀 YOLO Runner Starting..."

# Display runner type
if [[ "$REPOSITORY" != *"/"* ]]; then
    echo "🏢 Mode: Organization-level runner"
    echo "📍 Organization: ${REPOSITORY}"
else
    echo "📦 Mode: Repository-level runner"
    echo "📍 Repository: ${REPOSITORY}"
fi

# Get initial registration token
REG_TOKEN=$(get_token)

if [ -z "$REG_TOKEN" ]; then
    echo "❌ Could not obtain registration token"
    exit 1
fi

echo "✅ Registration token obtained"

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    
    # Get fresh token for removal
    REMOVAL_TOKEN=$(get_token 2>/dev/null)
    
    if [ -n "$REMOVAL_TOKEN" ]; then
        echo "🗑️  Removing runner registration..."
        ./config.sh remove --token "$REMOVAL_TOKEN" 2>/dev/null || true
    else
        echo "⚠️  Could not get removal token"
    fi
    
    rm -rf ./_work/* 2>/dev/null || true
    
    if [ "${DOCKER_SYSBOX_RUNTIME}" = "true" ]; then
        echo "🐳 Stopping Docker daemon..."
        sudo pkill --pidfile /home/runner/dockerd.pid 2>/dev/null || true
    fi
    
    echo "👋 Exiting..."
}

# Set up traps
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# Start Docker daemon if using Sysbox
if [ "${DOCKER_SYSBOX_RUNTIME}" = "true" ]; then
    echo "🐳 Starting Docker daemon..."
    sudo rm -f /home/runner/dockerd.pid
    sudo nohup /usr/bin/dockerd --pidfile /home/runner/dockerd.pid > /var/log/dockerd.log 2>&1 < /dev/null &
    
    echo "⏳ Waiting for Docker daemon..."
    for i in {1..30}; do
        if docker info > /dev/null 2>&1; then
            echo "✅ Docker daemon is ready!"
            break
        fi
        sleep 1
    done
    
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker daemon failed to start"
        exit 1
    fi
fi

# Configure runner (ephemeral mode)
echo "⚙️  Configuring runner..."
./config.sh \
    --url "https://github.com/${REPOSITORY}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME:-yolo-runner-$(hostname)}" \
    --labels "${RUNNER_LABELS:-self-hosted,linux,docker,yolo}" \
    --ephemeral \
    --unattended

# Unset sensitive variables
unset ACCESS_TOKEN
unset REG_TOKEN

echo ""
echo "🎯 YOLO MODE ACTIVATED!"
echo "🏃 Starting runner..."
echo ""

# Run the job and wait
./run.sh & wait $!