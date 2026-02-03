#!/usr/bin/env bash
set -euo pipefail

ANVIL_PORT=${ANVIL_PORT:-8545}
RPC_URL=${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}

# Default Anvil key (account 0) for the default mnemonic.
# You can override by exporting PRIVATE_KEY.
PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}

ANVIL_PID=""
KEEP_ANVIL_RUNNING=${KEEP_ANVIL_RUNNING:-1}
START_ANVIL=${START_ANVIL:-0}
ANVIL_FOREGROUND=${ANVIL_FOREGROUND:-0}
DEPLOY_PROTOCOL=${DEPLOY_PROTOCOL:-0}
FULL_SETUP=${FULL_SETUP:-1}

cleanup() {
  if [[ "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
    return
  fi
  if [[ -n "${ANVIL_PID}" ]]; then
    kill "${ANVIL_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "${START_ANVIL}" == "1" ]]; then
  echo "This script no longer starts Anvil."
  echo "Please start Anvil manually, then run: script/deploy_local.sh"
  exit 1
fi

export PRIVATE_KEY

if [[ "${DEPLOY_PROTOCOL}" == "1" ]]; then
  forge script script/DeployProtocol.s.sol:DeployProtocol \
    --rpc-url "${RPC_URL}" \
    --broadcast
fi

if [[ "${FULL_SETUP}" == "1" ]]; then
  forge script script/FullSetupLocal.s.sol:FullSetupLocal \
    --rpc-url "${RPC_URL}" \
    --broadcast
fi

if [[ -n "${ANVIL_PID}" && "${KEEP_ANVIL_RUNNING}" == "1" ]]; then
  echo "Anvil is running in this terminal. Press Ctrl+C to stop it."
  wait "${ANVIL_PID}"
fi
