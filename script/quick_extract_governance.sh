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

read -r PRICE_ORACLE GOVERNANCE_TOKEN PROTOCOL_TIMELOCK PROTOCOL_GOVERNOR <<<"$(python - <<PY
import json
path = "${RUN_JSON}"
with open(path, "r") as f:
    data = json.load(f)
creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE"]

def find_proxy(impl_name):
    impl = next((t for t in creates if t.get("contractName") == impl_name), None)
    if not impl:
        return ""
    impl_addr = (impl.get("contractAddress") or "").lower()
    for t in creates:
        if t.get("contractName") != "ERC1967Proxy":
            continue
        args = t.get("arguments") or []
        if len(args) >= 1 and str(args[0]).lower() == impl_addr:
            return t.get("contractAddress", "")
    return ""

print(
    find_proxy("PriceOracle"),
    find_proxy("GovernanceToken"),
    find_proxy("ProtocolTimelock"),
    find_proxy("ProtocolGovernor"),
)
PY
)"

if [[ -z "${PRICE_ORACLE}" || -z "${GOVERNANCE_TOKEN}" || -z "${PROTOCOL_TIMELOCK}" || -z "${PROTOCOL_GOVERNOR}" ]]; then
  echo "Missing required addresses (PRICE_ORACLE/GOVERNANCE_TOKEN/PROTOCOL_TIMELOCK/PROTOCOL_GOVERNOR)." >&2
  exit 1
fi

cat <<OUT
PRICE_ORACLE=${PRICE_ORACLE}
GOVERNANCE_TOKEN=${GOVERNANCE_TOKEN}
PROTOCOL_TIMELOCK=${PROTOCOL_TIMELOCK}
PROTOCOL_GOVERNOR=${PROTOCOL_GOVERNOR}
RPC_URL=${RPC_URL}
OUT
