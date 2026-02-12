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
PREPARE_GOVERNANCE_VOTERS=${PREPARE_GOVERNANCE_VOTERS:-0}
RUN_GOVERNANCE_UPGRADE_FLOW=${RUN_GOVERNANCE_UPGRADE_FLOW:-0}
GOVERNANCE_PHASE=${GOVERNANCE_PHASE:-prepare}
GAS_TOPUP_WEI=${GAS_TOPUP_WEI:-20000000000000000}
RUN_JSON=${RUN_JSON:-}
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

if [[ "${DEPLOY_PROTOCOL}" != "1" && "${FULL_SETUP}" != "1" && "${PREPARE_GOVERNANCE_VOTERS}" != "1" && "${RUN_GOVERNANCE_UPGRADE_FLOW}" != "1" ]]; then
  echo "Nothing to do. Enable at least one of DEPLOY_PROTOCOL/FULL_SETUP/PREPARE_GOVERNANCE_VOTERS/RUN_GOVERNANCE_UPGRADE_FLOW." >&2
  exit 1
fi

if [[ ("${DEPLOY_PROTOCOL}" == "1" || "${FULL_SETUP}" == "1") && "${VERIFY}" == "1" && -z "${ETHERSCAN_API_KEY}" ]]; then
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

resolve_run_json() {
  if [[ -n "${RUN_JSON}" ]]; then
    echo "${RUN_JSON}"
    return
  fi
  local candidate="broadcast/FullSetupLocal.s.sol/${EXPECTED_CHAIN_ID}/run-latest.json"
  if [[ -s "${candidate}" ]]; then
    echo "${candidate}"
    return
  fi
  ls -t broadcast/FullSetupLocal.s.sol/${EXPECTED_CHAIN_ID}/run-*.json 2>/dev/null | head -n 1 || true
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

if [[ "${PREPARE_GOVERNANCE_VOTERS}" == "1" ]]; then
  SEPOLIA_RUN_JSON="$(resolve_run_json)"
  if [[ -z "${SEPOLIA_RUN_JSON}" || ! -s "${SEPOLIA_RUN_JSON}" ]]; then
    echo "FullSetupLocal run JSON not found for chain ${EXPECTED_CHAIN_ID}. Set RUN_JSON or run FULL_SETUP=1 first." >&2
    exit 1
  fi
  echo "Preparing governance voters on Sepolia..."
  RPC_URL="${SEPOLIA_RPC_URL}" \
    RUN_JSON="${SEPOLIA_RUN_JSON}" \
    ADMIN_PK="${PRIVATE_KEY}" \
    GAS_TOPUP_WEI="${GAS_TOPUP_WEI}" \
    script/prepare_governance_voters.sh
fi

if [[ "${RUN_GOVERNANCE_UPGRADE_FLOW}" == "1" ]]; then
  SEPOLIA_RUN_JSON="$(resolve_run_json)"
  if [[ -z "${SEPOLIA_RUN_JSON}" || ! -s "${SEPOLIA_RUN_JSON}" ]]; then
    echo "FullSetupLocal run JSON not found for chain ${EXPECTED_CHAIN_ID}. Set RUN_JSON or run FULL_SETUP=1 first." >&2
    exit 1
  fi
  echo "Running governance upgrade phase on Sepolia: ${GOVERNANCE_PHASE}"
  RPC_URL="${SEPOLIA_RPC_URL}" \
    RUN_JSON="${SEPOLIA_RUN_JSON}" \
    ADMIN_PK="${PRIVATE_KEY}" \
    GOVERNANCE_PHASE="${GOVERNANCE_PHASE}" \
    AUTO_ADVANCE_TIME=0 \
    script/repro_governance_upgrade_flow.sh
fi

echo "Done."
