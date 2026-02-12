#!/usr/bin/env bash
set -euo pipefail

# Load variables from .env if present.
if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

RPC_URL=${RPC_URL:-${SEPOLIA_RPC_URL:-}}
RUN_JSON=${RUN_JSON:-}
WAIT_BUFFER_SECONDS=${WAIT_BUFFER_SECONDS:-1}
SLEEP_ENABLED=${SLEEP_ENABLED:-1}
RUN_PREPARE_VOTERS=${RUN_PREPARE_VOTERS:-1}
PRE_PROPOSE_SLEEP_SECONDS=${PRE_PROPOSE_SLEEP_SECONDS:-2}
MAX_WAIT_SECONDS=${MAX_WAIT_SECONDS:-300}
POLL_INTERVAL_SECONDS=${POLL_INTERVAL_SECONDS:-1}

# Governance voter keys (generated via `cast wallet new -n 3`)
# Alice: 0x913C5b1992632Fe8834074B02a8A35036E33Af9B
# Bob:   0xCc048528d2Ed6E30b8720D224f690BBb4aF71553
# Carol: 0x8e4E4F6970906cd7fA9928991dCB5FEb4Fd93D67
ALICE_PK=${ALICE_PK:-0xb773f7ce51225eba09c147f65c439189a96703cde5b3a5abb1f37c9c15028ad4}
BOB_PK=${BOB_PK:-0x6253d75e26f704a389d64caaf4deabb9b12797a4398714d84c6625802893c655}
CAROL_PK=${CAROL_PK:-0xea4c8c26c2a10611e24ce67cd235478d04bb7ad8f540d6f32f58f6e782f8b380}
export ALICE_PK BOB_PK CAROL_PK

if [[ -z "${RPC_URL}" ]]; then
  echo "RPC_URL (or SEPOLIA_RPC_URL) is required." >&2
  exit 1
fi

if ! cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
  echo "RPC_URL is not reachable: ${RPC_URL}" >&2
  exit 1
fi

CHAIN_ID=$(cast chain-id --rpc-url "${RPC_URL}")
if [[ -z "${RUN_JSON}" ]]; then
  RUN_JSON="broadcast/FullSetupLocal.s.sol/${CHAIN_ID}/run-latest.json"
fi

if [[ ! -s "${RUN_JSON}" ]]; then
  echo "RUN_JSON is missing or empty: ${RUN_JSON}" >&2
  echo "Set RUN_JSON explicitly or run FullSetupLocal first." >&2
  exit 1
fi

to_uint() {
  local raw
  raw=$(echo "$1" | sed '/^Warning:/d' | tr -d '\r' | xargs)
  if [[ "${raw}" == 0x* ]]; then
    cast to-dec "${raw}"
    return
  fi
  echo "${raw%% *}"
}

sleep_for() {
  local seconds="$1"
  if [[ "${seconds}" -le 0 ]]; then
    return
  fi
  if [[ "${SLEEP_ENABLED}" != "1" ]]; then
    echo "Skipping sleep (${seconds}s) because SLEEP_ENABLED=${SLEEP_ENABLED}"
    return
  fi
  echo "Sleeping ${seconds}s..."
  sleep "${seconds}"
}

run_phase() {
  local phase="$1"
  echo "Running governance phase: ${phase}"
  RPC_URL="${RPC_URL}" RUN_JSON="${RUN_JSON}" GOVERNANCE_PHASE="${phase}" script/repro_governance_upgrade_flow.sh
}

run_phase_with_retry() {
  local phase="$1"
  local max_attempts="${2:-20}"
  local retry_sleep="${3:-3}"
  local attempt=1

  while true; do
    if run_phase "${phase}"; then
      return 0
    fi

    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      echo "Phase ${phase} failed after ${attempt} attempts." >&2
      exit 1
    fi

    echo "Phase ${phase} not ready (attempt ${attempt}/${max_attempts}). Retrying in ${retry_sleep}s..."
    sleep_for "${retry_sleep}"
    attempt=$((attempt + 1))
  done
}

state_name() {
  case "$1" in
    0) echo "Pending" ;;
    1) echo "Active" ;;
    2) echo "Canceled" ;;
    3) echo "Defeated" ;;
    4) echo "Succeeded" ;;
    5) echo "Queued" ;;
    6) echo "Expired" ;;
    7) echo "Executed" ;;
    *) echo "Unknown($1)" ;;
  esac
}

proposal_state() {
  to_uint "$(cast call "${PROTOCOL_GOVERNOR}" "state(uint256)(uint8)" "${PROPOSAL_ID}" --rpc-url "${RPC_URL}")"
}

wait_for_proposal_state() {
  local label="$1"
  shift

  local deadline=$((SECONDS + MAX_WAIT_SECONDS))
  while true; do
    local current_state
    current_state=$(proposal_state)

    for expected in "$@"; do
      if [[ "${current_state}" -eq "${expected}" ]]; then
        echo "Proposal state ready for ${label}: $(state_name "${current_state}") (${current_state})"
        return 0
      fi
    done

    if [[ "${current_state}" -eq 2 || "${current_state}" -eq 3 || "${current_state}" -eq 6 || "${current_state}" -eq 7 ]]; then
      echo "Proposal entered terminal state before ${label}: $(state_name "${current_state}") (${current_state})" >&2
      exit 1
    fi

    if [[ "${SECONDS}" -ge "${deadline}" ]]; then
      echo "Timed out waiting for proposal state before ${label}. Current state: $(state_name "${current_state}") (${current_state})" >&2
      exit 1
    fi

    echo "Waiting for proposal state before ${label}... current: $(state_name "${current_state}") (${current_state})"
    sleep_for "${POLL_INTERVAL_SECONDS}"
  done
}

load_new_impl_state() {
  local state_file="cache/repro_governance_upgrade_flow/${CHAIN_ID}.env"
  if [[ -n "${NEW_PRICE_ORACLE_IMPL:-}" ]]; then
    return 0
  fi
  if [[ -s "${state_file}" ]]; then
    # shellcheck disable=SC1090
    source "${state_file}"
    export NEW_PRICE_ORACLE_IMPL
  fi
  if [[ -z "${NEW_PRICE_ORACLE_IMPL:-}" ]]; then
    echo "Failed to resolve NEW_PRICE_ORACLE_IMPL. Run prepare first." >&2
    exit 1
  fi
}

resolve_proposal_id() {
  local description_hash
  local upgrade_calldata
  description_hash=$(cast keccak "Upgrade PriceOracle")
  upgrade_calldata=$(cast calldata "upgradeToAndCall(address,bytes)" "${NEW_PRICE_ORACLE_IMPL}" "0x")
  to_uint "$(cast call "${PROTOCOL_GOVERNOR}" \
    "hashProposal(address[],uint256[],bytes[],bytes32)(uint256)" \
    "[${PRICE_ORACLE}]" \
    "[0]" \
    "[${upgrade_calldata}]" \
    "${description_hash}" \
    --rpc-url "${RPC_URL}")"
}

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

if [[ -z "${PRICE_ORACLE}" || -z "${PROTOCOL_GOVERNOR}" || -z "${PROTOCOL_TIMELOCK}" ]]; then
  echo "Missing required addresses (PRICE_ORACLE/PROTOCOL_GOVERNOR/PROTOCOL_TIMELOCK)." >&2
  exit 1
fi

VOTING_DELAY_SECONDS=$(to_uint "$(cast call "${PROTOCOL_GOVERNOR}" "votingDelay()(uint256)" --rpc-url "${RPC_URL}")")
VOTING_PERIOD_SECONDS=$(to_uint "$(cast call "${PROTOCOL_GOVERNOR}" "votingPeriod()(uint256)" --rpc-url "${RPC_URL}")")
TIMELOCK_DELAY_SECONDS=$(to_uint "$(cast call "${PROTOCOL_TIMELOCK}" "getMinDelay()(uint256)" --rpc-url "${RPC_URL}")")

echo "Detected Delays"
echo "  votingDelay:   ${VOTING_DELAY_SECONDS}s"
echo "  votingPeriod:  ${VOTING_PERIOD_SECONDS}s"
echo "  timelockDelay: ${TIMELOCK_DELAY_SECONDS}s"
echo "  waitBuffer:    ${WAIT_BUFFER_SECONDS}s"
echo "  preProposeSleep: ${PRE_PROPOSE_SLEEP_SECONDS}s"
echo "  runPrepareVoters: ${RUN_PREPARE_VOTERS}"
echo "  maxWait:       ${MAX_WAIT_SECONDS}s"
echo "  pollInterval:  ${POLL_INTERVAL_SECONDS}s"
echo ""

if [[ "${RUN_PREPARE_VOTERS}" == "1" ]]; then
  echo "Running governance voter preparation..."
  RPC_URL="${RPC_URL}" RUN_JSON="${RUN_JSON}" script/prepare_governance_voters.sh
fi

run_phase "prepare"
sleep_for "${PRE_PROPOSE_SLEEP_SECONDS}"
run_phase "propose"

load_new_impl_state
PROPOSAL_ID=$(resolve_proposal_id)
echo "Computed Proposal ID: ${PROPOSAL_ID}"

wait_for_proposal_state "vote" 1
run_phase_with_retry "vote"

wait_for_proposal_state "queue" 4
run_phase_with_retry "queue"

run_phase_with_retry "execute" 40 "${POLL_INTERVAL_SECONDS}"

echo "Governance upgrade flow finished."
