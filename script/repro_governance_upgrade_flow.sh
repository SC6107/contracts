#!/usr/bin/env bash
set -euo pipefail

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
RUN_JSON=${RUN_JSON:-$(ls -t broadcast/FullSetupLocal.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true)}
FOUNDRY_DISABLE_NIGHTLY_WARNING=${FOUNDRY_DISABLE_NIGHTLY_WARNING:-1}
GAS_ESTIMATE_MULTIPLIER=${GAS_ESTIMATE_MULTIPLIER:-200}
GOVERNANCE_PHASE=${GOVERNANCE_PHASE:-all}
STATE_DIR=${STATE_DIR:-cache/repro_governance_upgrade_flow}

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
CHAIN_ID=$(cast chain-id --rpc-url "${RPC_URL}")

mkdir -p "${STATE_DIR}"

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

echo "Resolved Addresses"
echo "  RPC_URL:            ${RPC_URL}"
echo "  PriceOracle:        ${PRICE_ORACLE}"
echo "  GovernanceToken:    ${GOVERNANCE_TOKEN}"
echo "  ProtocolTimelock:   ${PROTOCOL_TIMELOCK}"
echo "  ProtocolGovernor:   ${PROTOCOL_GOVERNOR}"
echo ""

to_uint() {
  local raw
  raw=$(echo "$1" | sed '/^Warning:/d' | tr -d '\r' | xargs)
  if [[ "${raw}" == 0x* ]]; then
    cast to-dec "${raw}"
    return
  fi
  echo "${raw%% *}"
}

advance_time() {
  local seconds="$1"
  if [[ "${seconds}" -le 0 ]]; then
    return
  fi
  if ! cast rpc --rpc-url "${RPC_URL}" evm_increaseTime "${seconds}" >/dev/null 2>&1; then
    cast rpc --rpc-url "${RPC_URL}" evm_increaseTime "[${seconds}]" >/dev/null
  fi
  if ! cast rpc --rpc-url "${RPC_URL}" evm_mine >/dev/null 2>&1; then
    cast rpc --rpc-url "${RPC_URL}" evm_mine "[]" >/dev/null
  fi
}

run_phase() {
  local phase="$1"
  echo "Running phase: ${phase}"
  if [[ -n "${NEW_PRICE_ORACLE_IMPL:-}" ]]; then
    PHASE="${phase}" NEW_PRICE_ORACLE_IMPL="${NEW_PRICE_ORACLE_IMPL}" \
      forge script script/repro_governance_upgrade_flow.s.sol:ReproGovernanceUpgradeFlow \
        --rpc-url "${RPC_URL}" \
        --broadcast \
        --gas-estimate-multiplier "${GAS_ESTIMATE_MULTIPLIER}"
    return
  fi

  PHASE="${phase}" forge script script/repro_governance_upgrade_flow.s.sol:ReproGovernanceUpgradeFlow \
    --rpc-url "${RPC_URL}" \
    --broadcast \
    --gas-estimate-multiplier "${GAS_ESTIMATE_MULTIPLIER}"
}

resolve_new_impl_from_run_json() {
  local path="$1"
  if [[ -z "${path}" || ! -s "${path}" ]]; then
    return
  fi
  python - <<PY
import json
path = "${path}"
with open(path, "r") as f:
    data = json.load(f)
creates = [t for t in data.get("transactions", []) if t.get("transactionType") == "CREATE" and t.get("contractName") == "PriceOracle"]
print(creates[-1].get("contractAddress", "") if creates else "")
PY
}

resolve_latest_repro_run_json() {
  ls -t broadcast/repro_governance_upgrade_flow.s.sol/*/run-latest.json 2>/dev/null | head -n 1 || true
}

is_manual_phase() {
  case "$1" in
    prepare|propose|vote|queue|execute) return 0 ;;
    *) return 1 ;;
  esac
}

state_file() {
  echo "${STATE_DIR}/${CHAIN_ID}.env"
}

save_new_impl_state() {
  local impl="$1"
  if [[ -z "${impl}" ]]; then
    return
  fi
  printf "NEW_PRICE_ORACLE_IMPL=%s\n" "${impl}" > "$(state_file)"
}

load_new_impl_state() {
  local f
  f="$(state_file)"
  if [[ -n "${NEW_PRICE_ORACLE_IMPL:-}" || ! -s "${f}" ]]; then
    return
  fi
  # shellcheck disable=SC1090
  source "${f}"
  export NEW_PRICE_ORACLE_IMPL
}

VOTING_DELAY_RAW=$(cast call "${PROTOCOL_GOVERNOR}" "votingDelay()(uint256)" --rpc-url "${RPC_URL}")
VOTING_PERIOD_RAW=$(cast call "${PROTOCOL_GOVERNOR}" "votingPeriod()(uint256)" --rpc-url "${RPC_URL}")
TIMELOCK_DELAY_RAW=$(cast call "${PROTOCOL_TIMELOCK}" "getMinDelay()(uint256)" --rpc-url "${RPC_URL}")

VOTING_DELAY_SECONDS=${VOTING_DELAY_SECONDS:-$(to_uint "${VOTING_DELAY_RAW}")}
VOTING_PERIOD_SECONDS=${VOTING_PERIOD_SECONDS:-$(to_uint "${VOTING_PERIOD_RAW}")}
TIMELOCK_DELAY_SECONDS=${TIMELOCK_DELAY_SECONDS:-$(to_uint "${TIMELOCK_DELAY_RAW}")}

echo "Delays"
echo "  Voting delay:       ${VOTING_DELAY_SECONDS}s"
echo "  Voting period:      ${VOTING_PERIOD_SECONDS}s"
echo "  Timelock delay:     ${TIMELOCK_DELAY_SECONDS}s"
echo ""

export ADMIN_PK ALICE_PK BOB_PK CAROL_PK PRICE_ORACLE GOVERNANCE_TOKEN PROTOCOL_TIMELOCK PROTOCOL_GOVERNOR

AUTO_ADVANCE_TIME=${AUTO_ADVANCE_TIME:-}
if [[ -z "${AUTO_ADVANCE_TIME}" ]]; then
  if [[ "${CHAIN_ID}" == "31337" ]]; then
    AUTO_ADVANCE_TIME="1"
  else
    AUTO_ADVANCE_TIME="0"
  fi
fi

if [[ "${GOVERNANCE_PHASE}" == "all" ]]; then
  if [[ "${AUTO_ADVANCE_TIME}" != "1" ]]; then
    echo "GOVERNANCE_PHASE=all requires local time control (evm_increaseTime)." >&2
    echo "For Sepolia/public RPC use phase mode:" >&2
    echo "  GOVERNANCE_PHASE=prepare|propose|vote|queue|execute script/repro_governance_upgrade_flow.sh" >&2
    exit 1
  fi

  run_phase "prepare"

  SCRIPT_RUN_JSON="$(resolve_latest_repro_run_json)"
  if [[ -z "${SCRIPT_RUN_JSON}" || ! -s "${SCRIPT_RUN_JSON}" ]]; then
    echo "Failed to find run-latest.json for repro_governance_upgrade_flow.s.sol." >&2
    exit 1
  fi

  NEW_PRICE_ORACLE_IMPL="$(resolve_new_impl_from_run_json "${SCRIPT_RUN_JSON}")"
  if [[ -z "${NEW_PRICE_ORACLE_IMPL}" ]]; then
    echo "Failed to resolve NEW_PRICE_ORACLE_IMPL from ${SCRIPT_RUN_JSON}" >&2
    exit 1
  fi

  save_new_impl_state "${NEW_PRICE_ORACLE_IMPL}"
  echo "Resolved NEW_PRICE_ORACLE_IMPL: ${NEW_PRICE_ORACLE_IMPL}"
  echo ""

  advance_time "2"
  run_phase "propose"

  advance_time "$((VOTING_DELAY_SECONDS + 1))"
  run_phase "vote"

  advance_time "$((VOTING_PERIOD_SECONDS + 1))"
  run_phase "queue"

  advance_time "$((TIMELOCK_DELAY_SECONDS + 1))"
  run_phase "execute"
  exit 0
fi

if ! is_manual_phase "${GOVERNANCE_PHASE}"; then
  echo "Invalid GOVERNANCE_PHASE: ${GOVERNANCE_PHASE}" >&2
  echo "Use one of: all, prepare, propose, vote, queue, execute" >&2
  exit 1
fi

if [[ "${GOVERNANCE_PHASE}" != "prepare" ]]; then
  load_new_impl_state
fi

if [[ "${GOVERNANCE_PHASE}" != "prepare" && -z "${NEW_PRICE_ORACLE_IMPL:-}" ]]; then
  SCRIPT_RUN_JSON="$(resolve_latest_repro_run_json)"
  NEW_PRICE_ORACLE_IMPL="$(resolve_new_impl_from_run_json "${SCRIPT_RUN_JSON}")"
  if [[ -z "${NEW_PRICE_ORACLE_IMPL}" ]]; then
    echo "NEW_PRICE_ORACLE_IMPL not set and not found in previous repro run." >&2
    echo "Run GOVERNANCE_PHASE=prepare first, or set NEW_PRICE_ORACLE_IMPL explicitly." >&2
    exit 1
  fi
  export NEW_PRICE_ORACLE_IMPL
  save_new_impl_state "${NEW_PRICE_ORACLE_IMPL}"
  echo "Using NEW_PRICE_ORACLE_IMPL from previous run: ${NEW_PRICE_ORACLE_IMPL}"
fi

run_phase "${GOVERNANCE_PHASE}"

if [[ "${GOVERNANCE_PHASE}" == "prepare" ]]; then
  SCRIPT_RUN_JSON="$(resolve_latest_repro_run_json)"
  PREPARED_IMPL="$(resolve_new_impl_from_run_json "${SCRIPT_RUN_JSON}")"
  if [[ -n "${PREPARED_IMPL}" ]]; then
    save_new_impl_state "${PREPARED_IMPL}"
  fi
fi

case "${GOVERNANCE_PHASE}" in
  prepare)
    echo "Next: run GOVERNANCE_PHASE=propose"
    ;;
  propose)
    echo "Next: wait at least ${VOTING_DELAY_SECONDS}s, then run GOVERNANCE_PHASE=vote"
    ;;
  vote)
    echo "Next: wait at least ${VOTING_PERIOD_SECONDS}s, then run GOVERNANCE_PHASE=queue"
    ;;
  queue)
    echo "Next: wait at least ${TIMELOCK_DELAY_SECONDS}s, then run GOVERNANCE_PHASE=execute"
    ;;
esac
