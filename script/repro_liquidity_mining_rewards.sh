#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
RUN_JSON=${RUN_JSON:-$(ls -t broadcast/FullSetupLocal.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)}
FOUNDRY_DISABLE_NIGHTLY_WARNING=${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}

# Default Anvil account private keys (mnemonic: test test ... junk)
ADMIN_PK=${ADMIN_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
ALICE_PK=${ALICE_PK:-0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba}
BOB_PK=${BOB_PK:-0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e}

if [[ -z "${RUN_JSON}" ]]; then
  echo "RUN_JSON not found. Set RUN_JSON or run FullSetupLocal first." >&2
  exit 1
fi
if [[ ! -s "${RUN_JSON}" ]]; then
  echo "RUN_JSON is missing or empty: ${RUN_JSON}" >&2
  exit 1
fi
if ! cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
  echo "RPC_URL is not reachable: ${RPC_URL}" >&2
  exit 1
fi

export FOUNDRY_DISABLE_NIGHTLY_WARNING

ENV_OUTPUT=$(script/quick_extract_local.sh)
if [[ -z "${ENV_OUTPUT}" ]]; then
  echo "Failed to extract addresses." >&2
  exit 1
fi

# shellcheck disable=SC1090
eval "${ENV_OUTPUT}"

if [[ -z "${GOVERNANCE_TOKEN}" || -z "${USDC}" || -z "${DUSDC}" || -z "${USDC_MINING}" ]]; then
  echo "Missing required addresses (GOVERNANCE_TOKEN/USDC/DUSDC/USDC_MINING)." >&2
  exit 1
fi

echo "Resolved Addresses"
echo "  RPC_URL:           ${RPC_URL}"
echo "  GOV Token:         ${GOVERNANCE_TOKEN}"
echo "  USDC:              ${USDC}"
echo "  dUSDC:             ${DUSDC}"
echo "  USDC Mining:       ${USDC_MINING}"
echo ""

export ADMIN_PK ALICE_PK BOB_PK GOVENANCE_TOKEN GOVERNANCE_TOKEN USDC DUSDC USDC_MINING

forge script script/repro_liquidity_mining_rewards.s.sol:ReproLiquidityMiningRewards \
  --rpc-url "${RPC_URL}" \
  --broadcast
