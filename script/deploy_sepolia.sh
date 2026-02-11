#!/usr/bin/env bash
set -euo pipefail

# Load variables from .env if present.
if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

SEPOLIA_RPC_URL=${SEPOLIA_RPC_URL:-}
PRIVATE_KEY=${PRIVATE_KEY:-${DEV_PRIVATE_KEY:-}}
ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-}
VERIFY=${VERIFY:-1}
DEPLOY_PROTOCOL=${DEPLOY_PROTOCOL:-1}
FULL_SETUP=${FULL_SETUP:-1}
CONFIRM_NETWORK=${CONFIRM_NETWORK:-YES}
SLOW_BROADCAST=${SLOW_BROADCAST:-1}
MAX_BROADCAST_ATTEMPTS=${MAX_BROADCAST_ATTEMPTS:-3}
RETRY_SLEEP_SECONDS=${RETRY_SLEEP_SECONDS:-3}
START_WITH_RESUME=${START_WITH_RESUME:-0}

EXPECTED_CHAIN_ID=11155111

if [[ -z "${SEPOLIA_RPC_URL}" ]]; then
  echo "SEPOLIA_RPC_URL is required" >&2
  exit 1
fi

if [[ -z "${PRIVATE_KEY}" ]]; then
  echo "PRIVATE_KEY or DEV_PRIVATE_KEY is required" >&2
  exit 1
fi

if [[ "${DEPLOY_PROTOCOL}" != "1" && "${FULL_SETUP}" != "1" ]]; then
  echo "Nothing to deploy. Set DEPLOY_PROTOCOL=1 and/or FULL_SETUP=1." >&2
  exit 1
fi

if [[ "${VERIFY}" == "1" && -z "${ETHERSCAN_API_KEY}" ]]; then
  echo "ETHERSCAN_API_KEY is required when VERIFY=1" >&2
  exit 1
fi

CHAIN_ID=$(cast chain-id --rpc-url "${SEPOLIA_RPC_URL}" 2>/dev/null || true)
if [[ -z "${CHAIN_ID}" ]]; then
  echo "Failed to fetch chain-id from SEPOLIA_RPC_URL." >&2
  exit 1
fi

if [[ "${CHAIN_ID}" != "${EXPECTED_CHAIN_ID}" ]]; then
  echo "Wrong network. Expected chain-id ${EXPECTED_CHAIN_ID} (Sepolia), got ${CHAIN_ID}." >&2
  exit 1
fi

if [[ "${CONFIRM_NETWORK}" != "YES" ]]; then
  echo "Set CONFIRM_NETWORK=YES to run on Sepolia (chain-id ${CHAIN_ID})." >&2
  exit 1
fi

export PRIVATE_KEY

run_forge_script() {
  local target="$1"
  local base_cmd=(
    forge script "${target}"
    --rpc-url "${SEPOLIA_RPC_URL}"
    --broadcast
  )

  if [[ "${SLOW_BROADCAST}" == "1" ]]; then
    base_cmd+=(--slow)
  fi

  if [[ "${VERIFY}" == "1" ]]; then
    base_cmd+=(
      --verify
      --etherscan-api-key "${ETHERSCAN_API_KEY}"
    )
  fi

  local attempt=1
  local use_resume="${START_WITH_RESUME}"

  while (( attempt <= MAX_BROADCAST_ATTEMPTS )); do
    local cmd=("${base_cmd[@]}")
    if [[ "${use_resume}" == "1" ]]; then
      cmd+=(--resume)
      echo "Attempt ${attempt}/${MAX_BROADCAST_ATTEMPTS}: retrying with --resume for ${target}"
    else
      echo "Attempt ${attempt}/${MAX_BROADCAST_ATTEMPTS}: broadcasting ${target}"
    fi

    set +e
    "${cmd[@]}"
    local status=$?
    set -e

    if [[ "${status}" == "0" ]]; then
      return 0
    fi

    if (( attempt == MAX_BROADCAST_ATTEMPTS )); then
      echo "Broadcast failed for ${target} after ${MAX_BROADCAST_ATTEMPTS} attempts." >&2
      return "${status}"
    fi

    echo "Broadcast failed (exit ${status}). Retrying in ${RETRY_SLEEP_SECONDS}s..." >&2
    sleep "${RETRY_SLEEP_SECONDS}"
    use_resume=1
    ((attempt++))
  done
}

if [[ "${DEPLOY_PROTOCOL}" == "1" ]]; then
  echo "Deploying DeployProtocol to Sepolia..."
  run_forge_script "script/DeployProtocol.s.sol:DeployProtocol"
fi

if [[ "${FULL_SETUP}" == "1" ]]; then
  echo "Deploying FullSetupLocal to Sepolia..."
  echo "Note: FullSetupLocal deploys mock tokens/feeds and seeds local-style test data."
  run_forge_script "script/FullSetupLocal.s.sol:FullSetupLocal"
fi

echo "Done."
