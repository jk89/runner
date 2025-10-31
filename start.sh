#!/bin/bash
set -euo pipefail

cd /home/runner/actions

get_token() {
  if [[ "${REPOSITORY:-}" != *"/"* ]]; then
    api="orgs/${REPOSITORY}"
  else
    api="repos/${REPOSITORY}"
  fi

  echo "🔑 Requesting token from ${api}..." >&2
  curl -fsS -X POST -H "Authorization: token ${ACCESS_TOKEN}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/${api}/actions/runners/registration-token" | jq -r '.token // empty'
}

: "${REPOSITORY:?REPOSITORY not set (eg: owner/repo)}"
: "${ACCESS_TOKEN:?ACCESS_TOKEN not set (classic PAT with repo scope)}"

echo "🚀 YOLO Runner Starting..."
if [[ "$REPOSITORY" != *"/"* ]]; then
  echo "🏢 Mode: org-level ($REPOSITORY)"
else
  echo "📦 Mode: repo-level ($REPOSITORY)"
fi

REG_TOKEN="$(get_token)"
if [[ -z "$REG_TOKEN" ]]; then
  echo "❌ Could not obtain registration token"
  exit 1
fi
echo "✅ Registration token obtained"

cleanup() {
  echo ""
  echo "🧹 Cleaning up..."
  REMOVAL_TOKEN="$(get_token 2>/dev/null || true)"
  if [[ -n "$REMOVAL_TOKEN" ]]; then
    echo "🗑️  Removing runner registration..."
    ./config.sh remove --token "$REMOVAL_TOKEN" 2>/dev/null || true
  fi
  rm -rf ./_work/* 2>/dev/null || true

  if [[ "${DOCKER_SYSBOX_RUNTIME:-}" == "true" ]]; then
    echo "🐳 Stopping Docker daemon..."
    sudo pkill --pidfile /home/runner/dockerd.pid 2>/dev/null || true
  fi
  echo "👋 Exiting..."
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup' EXIT

# Start Docker daemon only via sudo (runner can run this; sudoers allows it)
if [[ "${DOCKER_SYSBOX_RUNTIME:-}" == "true" ]]; then
  echo "🐳 Starting Docker daemon (sudo) ..."
  sudo rm -f /home/runner/dockerd.pid 2>/dev/null || true
  mkdir -p /home/runner/logs
  sudo /usr/bin/dockerd --pidfile /home/runner/dockerd.pid &
  echo "⏳ Waiting for Docker socket..."
  for i in {1..30}; do
    if [[ -S /var/run/docker.sock ]]; then
      sudo chmod 666 /var/run/docker.sock
      if docker info > /dev/null 2>&1; then
        echo "✅ Docker daemon ready"
        break
      fi
    fi
    sleep 1
  done
fi

# Configure ephemeral runner (runs as non-root runner user)
echo "⚙️  Configuring runner..."
./config.sh \
  --url "https://github.com/${REPOSITORY}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME:-yolo-runner-$(hostname)}" \
  --labels "${RUNNER_LABELS:-self-hosted,linux,docker,yolo}" \
  --ephemeral \
  --unattended

unset ACCESS_TOKEN
unset REG_TOKEN

echo ""
echo "🎯 YOLO MODE ACTIVATED!"
echo "🏃 Starting runner..."
./run.sh & wait $!
