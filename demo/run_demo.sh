#!/usr/bin/env bash
set -euo pipefail
: "${VAULT:?set VAULT}"; : "${PK:?set PK}"
RPC=https://atlantic.dplabs-internal.com
TARGET=${TARGET:?set TARGET recipient}
FIRE=$(( $(date +%s) + 60 ))
EXP=$(( $(date +%s) + 3600 ))

echo "Scheduling a time intent firing in ~60s..."
cast send "$VAULT" "scheduleIntent(address,bytes,(uint8,address,uint256),uint64)" \
  "$TARGET" 0x "(0,0x0000000000000000000000000000000000000000,$FIRE)" "$EXP" \
  --value 0.01ether --rpc-url $RPC --private-key $PK
ID=$(( $(cast call "$VAULT" "intentCount()(uint256)" --rpc-url $RPC) - 1 ))
echo "intent id=$ID"

echo "Polling canExecute (the keeper loop)..."
until [ "$(cast call "$VAULT" "canExecute(uint256)(bool)" "$ID" --rpc-url $RPC)" = "true" ]; do
  sleep 10; echo "  not yet..."
done
echo "Condition met -> executing"
cast send "$VAULT" "execute(uint256)" "$ID" --rpc-url $RPC --private-key $PK
echo "Done. Intent settled on-chain."
