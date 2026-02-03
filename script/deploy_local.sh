#!/usr/bin/env bash
set -euo pipefail

ANVIL_PORT=${ANVIL_PORT:-8545}
RPC_URL=${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}

# Default Anvil key (account 0) for the default mnemonic.
# You can override by exporting PRIVATE_KEY.
PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}

ANVIL_PID=""
KEEP_ANVIL_RUNNING=${KEEP_ANVIL_RUNNING:-1}

cleanup() {
  if [[ "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
    return
  fi
  if [[ -n "${ANVIL_PID}" ]]; then
    kill "${ANVIL_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Try to start anvil. If the port is already in use, assume anvil is running.
# Run it in the background so we can deploy, then wait on it to keep it in the foreground.
anvil --port "${ANVIL_PORT}" &
ANVIL_PID=$!

# Give anvil a moment to start; if it exits immediately, keep going.
sleep 0.5
if ! kill -0 "${ANVIL_PID}" >/dev/null 2>&1; then
  ANVIL_PID=""
  echo "Anvil did not start (port ${ANVIL_PORT} may already be in use). Continuing..."
else
  echo "Anvil started (pid ${ANVIL_PID}) on ${RPC_URL}"
fi

export PRIVATE_KEY

forge script script/DeployProtocol.s.sol:DeployProtocol \
  --rpc-url "${RPC_URL}" \
  --broadcast

if [[ -n "${ANVIL_PID}" && "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
  echo "Anvil is running in this terminal. Press Ctrl+C to stop it."
  wait "${ANVIL_PID}"
fi
