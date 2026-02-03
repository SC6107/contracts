#!/usr/bin/env bash
set -euo pipefail

ANVIL_PORT=${ANVIL_PORT:-8545}
RPC_URL=${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}
PRIVATE_KEY=${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
SKIP_DEPLOY=${SKIP_DEPLOY:-1}
PRICE_ORACLE_PROXY=${PRICE_ORACLE_PROXY:-}

export PRIVATE_KEY

if [[ "${SKIP_DEPLOY}" != "1" ]]; then
  echo "Deploying protocol to ${RPC_URL}..."
  forge script script/DeployProtocol.s.sol:DeployProtocol \
    --rpc-url "${RPC_URL}" \
    --broadcast
fi

if [[ -z "${PRICE_ORACLE_PROXY}" ]]; then
  if [[ -x script/quick_extract_local.sh ]]; then
    ENV_OUTPUT=$(script/quick_extract_local.sh 2>/dev/null || true)
    if [[ -n "${ENV_OUTPUT}" ]]; then
      # shellcheck disable=SC1090
      eval "${ENV_OUTPUT}"
      if [[ -n "${PRICE_ORACLE:-}" ]]; then
        PRICE_ORACLE_PROXY="${PRICE_ORACLE}"
      fi
    fi
  fi
fi

if [[ -z "${PRICE_ORACLE_PROXY}" ]]; then
  RUN_JSON=$(ls -t broadcast/FullSetupLocal.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)
  if [[ -z "${RUN_JSON}" ]]; then
    RUN_JSON=$(ls -t broadcast/DeployProtocol.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)
  fi
  if [[ -z "${RUN_JSON}" ]]; then
    echo "No broadcast file found. Set PRICE_ORACLE_PROXY or run deploy."
    exit 1
  fi

  PRICE_ORACLE_PROXY=$(python - <<PY
import json
path = "${RUN_JSON}"
with open(path, "r") as f:
    data = json.load(f)

creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE"]
price_impl = next((t for t in creates if t.get("contractName") == "PriceOracle"), None)
if not price_impl:
    raise SystemExit(1)

impl_addr = price_impl["contractAddress"].lower()
proxy = None
for t in creates:
    if t.get("contractName") != "ERC1967Proxy":
        continue
    args = t.get("arguments") or []
    if len(args) >= 1 and str(args[0]).lower() == impl_addr:
        proxy = t
        break

if not proxy:
    raise SystemExit(1)

print(proxy["contractAddress"])
PY
) || {
    echo "Failed to parse PriceOracle proxy address from ${RUN_JSON}."
    exit 1
  }
fi

echo "PriceOracle proxy: ${PRICE_ORACLE_PROXY}"

if command -v cast >/dev/null 2>&1; then
  echo "Version before:"
  if ! cast call "${PRICE_ORACLE_PROXY}" "version()(uint256)" --rpc-url "${RPC_URL}" >/dev/null; then
    echo "PriceOracle proxy does not respond to version()." >&2
    echo "The broadcast file may be stale for this chain. Re-run FullSetupLocal or set PRICE_ORACLE_PROXY." >&2
    exit 1
  fi
  cast call "${PRICE_ORACLE_PROXY}" "version()(uint256)" --rpc-url "${RPC_URL}"
fi

forge script script/UpgradeProtocol.s.sol:UpgradeProtocol \
  --sig "upgradePriceOracle(address)" "${PRICE_ORACLE_PROXY}" \
  --rpc-url "${RPC_URL}" \
  --broadcast

if command -v cast >/dev/null 2>&1; then
  echo "Version after:"
  cast call "${PRICE_ORACLE_PROXY}" "version()(uint256)" --rpc-url "${RPC_URL}"
fi

echo "Upgrade test complete."
