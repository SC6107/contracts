#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
RUN_JSON=${RUN_JSON:-$(ls -t broadcast/FullSetupLocal.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)}
FOUNDRY_DISABLE_NIGHTLY_WARNING=${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}
GAS_ESTIMATE_MULTIPLIER=${GAS_ESTIMATE_MULTIPLIER:-200}
GAS_TOPUP_WEI=${GAS_TOPUP_WEI:-10000000000000000000}

# Default to deployer key from env on public networks, fallback to Anvil account 0 key.
ADMIN_PK=${ADMIN_PK:-${PRIVATE_KEY:-${DEV_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}}}
ALICE_PK=${ALICE_PK:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}
BOB_PK=${BOB_PK:-0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a}
CAROL_PK=${CAROL_PK:-0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6}

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

if [[ -z "${GOVERNANCE_TOKEN}" ]]; then
  echo "Missing required address: GOVERNANCE_TOKEN." >&2
  exit 1
fi

echo "Preparing governance voters"
echo "  RPC_URL:          ${RPC_URL}"
echo "  GovernanceToken:  ${GOVERNANCE_TOKEN}"
echo ""

export ADMIN_PK ALICE_PK BOB_PK CAROL_PK GOVERNANCE_TOKEN
export GAS_TOPUP_WEI

forge script script/prepare_governance_voters.s.sol:PrepareGovernanceVoters \
  --rpc-url "${RPC_URL}" \
  --broadcast \
  --gas-estimate-multiplier "${GAS_ESTIMATE_MULTIPLIER}"
