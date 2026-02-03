#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-}
PRIVATE_KEY=${PRIVATE_KEY:-}
PROXY_ADDRESS=${PROXY_ADDRESS:-}
UPGRADE_KIND=${UPGRADE_KIND:-}
CONFIRM_NETWORK=${CONFIRM_NETWORK:-}
DRY_RUN=${DRY_RUN:-0}

if [[ -z "${RPC_URL}" ]]; then
  echo "RPC_URL is required" >&2
  exit 1
fi
if [[ -z "${PRIVATE_KEY}" ]]; then
  echo "PRIVATE_KEY is required" >&2
  exit 1
fi
if [[ -z "${PROXY_ADDRESS}" ]]; then
  echo "PROXY_ADDRESS is required" >&2
  exit 1
fi
if [[ -z "${UPGRADE_KIND}" ]]; then
  echo "UPGRADE_KIND is required (price_oracle|comptroller|lending_token|governance_token|liquidity_mining)" >&2
  exit 1
fi

CHAIN_ID=$(cast chain-id --rpc-url "${RPC_URL}" 2>/dev/null || true)
if [[ -z "${CHAIN_ID}" ]]; then
  echo "Failed to fetch chain-id from RPC_URL." >&2
  exit 1
fi
if [[ "${CONFIRM_NETWORK}" != "YES" ]]; then
  echo "Set CONFIRM_NETWORK=YES to run. Detected chain-id: ${CHAIN_ID}" >&2
  exit 1
fi

SIG=""
case "${UPGRADE_KIND}" in
  price_oracle)
    SIG='upgradePriceOracle(address)'
    ;;
  comptroller)
    SIG='upgradeComptroller(address)'
    ;;
  lending_token)
    SIG='upgradeLendingToken(address)'
    ;;
  governance_token)
    SIG='upgradeGovernanceToken(address)'
    ;;
  liquidity_mining)
    SIG='upgradeLiquidityMining(address)'
    ;;
  *)
    echo "Unknown UPGRADE_KIND: ${UPGRADE_KIND}" >&2
    exit 1
    ;;
 esac

BROADCAST_FLAG="--broadcast"
if [[ "${DRY_RUN}" == "1" ]]; then
  BROADCAST_FLAG=""
fi

export PRIVATE_KEY

echo "Upgrading ${UPGRADE_KIND} at ${PROXY_ADDRESS} on mainnet..."
forge script script/UpgradeProtocol.s.sol:UpgradeProtocol \
  --sig "${SIG}" "${PROXY_ADDRESS}" \
  --rpc-url "${RPC_URL}" \
  ${BROADCAST_FLAG}

echo "Done."
