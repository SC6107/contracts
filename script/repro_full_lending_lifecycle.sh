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
  echo "Run FullSetupLocal with --broadcast, or set RUN_JSON to a valid file." >&2
  exit 1
fi

if ! cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
  echo "RPC_URL is not reachable: ${RPC_URL}" >&2
  exit 1
fi

export FOUNDRY_DISABLE_NIGHTLY_WARNING

PROXIES="$(python - <<PY
import json
path = "${RUN_JSON}"
with open(path, "r") as f:
    data = json.load(f)
creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE"]
proxies = [t.get("contractAddress") for t in creates if t.get("contractName") == "ERC1967Proxy"]
print(" ".join([p for p in proxies if p]))
PY
)"

COMPTROLLER=""
for proxy in ${PROXIES}; do
  if MARKETS_RAW=$(cast call "${proxy}" "getAllMarkets()(address[])" --rpc-url "${RPC_URL}" 2>/dev/null); then
    if [[ -n "${MARKETS_RAW}" ]]; then
      COMPTROLLER="${proxy}"
      break
    fi
  fi
done

if [[ -z "${COMPTROLLER}" ]]; then
  echo "Failed to resolve Comptroller from ${RUN_JSON}" >&2
  exit 1
fi

MARKETS_RAW=$(cast call "${COMPTROLLER}" "getAllMarkets()(address[])" --rpc-url "${RPC_URL}" | sed '/^Warning:/d')
if [[ -z "${MARKETS_RAW}" ]]; then
  echo "Failed to read markets from Comptroller. Is it deployed and initialized?" >&2
  exit 1
fi

# Expected format: [0x..., 0x...]
MARKETS=$(echo "${MARKETS_RAW}" | tr -d '[],' )

DUSDC=""
DWETH=""
USDC=""
WETH=""
for market in ${MARKETS}; do
  underlying=$(cast call "${market}" "underlying()(address)" --rpc-url "${RPC_URL}")
  symbol=$(cast call "${underlying}" "symbol()(string)" --rpc-url "${RPC_URL}" | sed '/^Warning:/d' | tr -d '\r' | tr -d '"')
  if [[ "${symbol}" == "USDC" ]]; then
    USDC="${underlying}"
    DUSDC="${market}"
  elif [[ "${symbol}" == "WETH" ]]; then
    WETH="${underlying}"
    DWETH="${market}"
  fi
 done

if [[ -z "${USDC}" || -z "${WETH}" || -z "${DUSDC}" || -z "${DWETH}" ]]; then
  echo "Failed to resolve USDC/WETH or dUSDC/dWETH from comptroller markets." >&2
  exit 1
fi

export ADMIN_PK ALICE_PK BOB_PK COMPTROLLER USDC WETH DUSDC DWETH

forge script script/repro_full_lending_lifecycle.s.sol:ReproFullLendingLifecycle \
  --rpc-url "${RPC_URL}" \
  --broadcast
