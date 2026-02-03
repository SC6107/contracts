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

read -r PRICE_ORACLE GOVERNANCE_TOKEN TIMELOCK GOVERNOR <<<"$(python - <<PY
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

price_oracle = find_proxy("PriceOracle")
governance_token = find_proxy("GovernanceToken")
timelock = find_proxy("ProtocolTimelock")
governor = find_proxy("ProtocolGovernor")

print(price_oracle, governance_token, timelock, governor)
PY
)"

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

USDC_MINING=""
WETH_MINING=""
MINING_PROXIES=$(python - <<PY
import json
path = "${RUN_JSON}"
with open(path, "r") as f:
    data = json.load(f)
creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE"]
mining_impls = [t for t in creates if t.get("contractName") == "LiquidityMining"]
impl_addrs = {m.get("contractAddress","").lower() for m in mining_impls}
proxies = []
for t in creates:
    if t.get("contractName") != "ERC1967Proxy":
        continue
    args = t.get("arguments") or []
    if len(args) >= 1 and str(args[0]).lower() in impl_addrs:
        proxies.append(t.get("contractAddress"))
print(" ".join(proxies))
PY
)

for proxy in ${MINING_PROXIES}; do
  staking=$(cast call "${proxy}" "stakingToken()(address)" --rpc-url "${RPC_URL}")
  if [[ "$(echo "${staking}" | tr '[:upper:]' '[:lower:]')" == "$(echo "${DUSDC}" | tr '[:upper:]' '[:lower:]')" ]]; then
    USDC_MINING="${proxy}"
  elif [[ "$(echo "${staking}" | tr '[:upper:]' '[:lower:]')" == "$(echo "${DWETH}" | tr '[:upper:]' '[:lower:]')" ]]; then
    WETH_MINING="${proxy}"
  fi
done

cat <<OUT
COMPTROLLER=${COMPTROLLER}
PRICE_ORACLE=${PRICE_ORACLE}
GOVERNANCE_TOKEN=${GOVERNANCE_TOKEN}
PROTOCOL_TIMELOCK=${TIMELOCK}
PROTOCOL_GOVERNOR=${GOVERNOR}
USDC=${USDC}
WETH=${WETH}
DUSDC=${DUSDC}
DWETH=${DWETH}
USDC_FEED=${USDC_FEED}
WETH_FEED=${WETH_FEED}
USDC_MINING=${USDC_MINING}
WETH_MINING=${WETH_MINING}
RPC_URL=${RPC_URL}
OUT
