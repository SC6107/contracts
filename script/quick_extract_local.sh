#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
RUN_JSON=${RUN_JSON:-$(ls -t broadcast/FullSetupLocal.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)}
FOUNDRY_DISABLE_NIGHTLY_WARNING=${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}

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

read -r COMPTROLLER PRICE_ORACLE <<<"$(python - <<PY
import json
path = "${RUN_JSON}"
with open(path, "r") as f:
    data = json.load(f)
creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE"]

def find_proxy(impl_name):
    impl = next((t for t in creates if t.get("contractName") == impl_name), None)
    if not impl:
        return ""
    impl_addr = impl["contractAddress"].lower()
    for t in creates:
        if t.get("contractName") != "ERC1967Proxy":
            continue
        args = t.get("arguments") or []
        if len(args) >= 1 and str(args[0]).lower() == impl_addr:
            return t["contractAddress"]
    return ""

comptroller = find_proxy("Comptroller")
price_oracle = find_proxy("PriceOracle")

print(comptroller, price_oracle)
PY
)"

if [[ -z "${COMPTROLLER}" || -z "${PRICE_ORACLE}" ]]; then
  echo "Failed to resolve Comptroller or PriceOracle from ${RUN_JSON}" >&2
  exit 1
fi

MARKETS_RAW=$(cast call "${COMPTROLLER}" "getAllMarkets()(address[])" --rpc-url "${RPC_URL}" | sed '/^Warning:/d')
if [[ -z "${MARKETS_RAW}" ]]; then
  echo "Failed to read markets from Comptroller." >&2
  exit 1
fi

MARKETS=$(echo "${MARKETS_RAW}" | tr -d '[],' )

USDC=""
WETH=""
DUSDC=""
DWETH=""

for market in ${MARKETS}; do
  underlying=$(cast call "${market}" "underlying()(address)" --rpc-url "${RPC_URL}")
  symbol=$(cast call "${underlying}" "symbol()(string)" --rpc-url "${RPC_URL}" | sed '/^Warning:/d' | tr -d '\r' | tr -d '"')
  printf "MARKET=%s\nUNDERLYING=%s\nSYMBOL=%s\n\n" "${market}" "${underlying}" "${symbol}"
  if [[ "${symbol}" == "USDC" ]]; then
    USDC="${underlying}"
    DUSDC="${market}"
  elif [[ "${symbol}" == "WETH" ]]; then
    WETH="${underlying}"
    DWETH="${market}"
  fi
 done

if [[ -z "${USDC}" || -z "${WETH}" || -z "${DUSDC}" || -z "${DWETH}" ]]; then
  echo "Failed to resolve USDC/WETH or dUSDC/dWETH from markets." >&2
  exit 1
fi

USDC_FEED=$(cast call "${PRICE_ORACLE}" "getAssetSource(address)(address)" "${USDC}" --rpc-url "${RPC_URL}")
WETH_FEED=$(cast call "${PRICE_ORACLE}" "getAssetSource(address)(address)" "${WETH}" --rpc-url "${RPC_URL}")

cat <<OUT
COMPTROLLER=${COMPTROLLER}
PRICE_ORACLE=${PRICE_ORACLE}
USDC=${USDC}
WETH=${WETH}
DUSDC=${DUSDC}
DWETH=${DWETH}
USDC_FEED=${USDC_FEED}
WETH_FEED=${WETH_FEED}
RPC_URL=${RPC_URL}
OUT
