# IntentVault Reference

> **Network Configuration:** All commands use Atlantic testnet RPC `https://atlantic.dplabs-internal.com`
> (chain ID 688689). Set `RPC=https://atlantic.dplabs-internal.com` and `VAULT=__VAULT_ADDRESS__`
> in your shell before running any command below.
>
> **Private Key Configuration:** Set `export PRIVATE_KEY=0x<your-key>` for write operations.
> Never log or commit this value. Read-only calls (`cast call`) do not require it.

---

## Schedule a Time-Based Intent {#schedule-time}

Escrow PHRS and register an intent that becomes executable at or after a specific Unix timestamp.
An executor (agent, keeper, or any EOA) calls `execute` once the time threshold is reached.

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__

# Inputs
TARGET=<recipient-or-contract-address>
FIRE_AT=<unix-seconds>          # when the call should become executable
EXPIRY=<unix-seconds>           # deadline; must be > FIRE_AT, MUST be > now
VALUE_WEI=<wei-to-escrow>       # PHRS to lock in escrow (0 for data-only calls)

cast send "$VAULT" \
  "scheduleIntent(address,bytes,(uint8,address,uint256),uint64)" \
  "$TARGET" \
  "0x" \
  "(0,0x0000000000000000000000000000000000000000,$FIRE_AT)" \
  "$EXPIRY" \
  --value "$VALUE_WEI" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"
```

For a plain PHRS transfer set `data` to `0x` (empty bytes). To call a contract function, replace `0x` with ABI-encoded calldata (e.g. `cast calldata "myFunc(uint256)" 42`).

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `target` | `address` | Recipient or contract to call on settlement. Must be non-zero and not the vault itself. |
| `data` | `bytes` | Calldata for the target call. Use `0x` for a plain native transfer. |
| `condition` tuple `cType` | `uint8` | `0` = TIME |
| `condition` tuple `subject` | `address` | Unused for TIME; pass `0x0000000000000000000000000000000000000000` |
| `condition` tuple `threshold` | `uint256` | Unix timestamp (seconds) at or after which the condition is met |
| `expiry` | `uint64` | Deadline in Unix seconds. Intent cannot be executed after this point. |
| `--value` | wei | PHRS to escrow for this intent. Sent to target on settlement. |

### Output Parsing

The transaction receipt contains an `IntentScheduled` log. Decode the assigned ID:

```bash
# Read the current intentCount immediately after the transaction to get the last ID
ID=$(( $(cast call "$VAULT" "intentCount()(uint256)" --rpc-url "$RPC") - 1 ))
echo "Scheduled intent ID: $ID"
```

Alternatively, parse the `IntentScheduled(uint256 indexed id, ...)` topic from the receipt logs.

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `ZeroTarget` | `target` is the zero address | Provide a valid non-zero address |
| `SelfCallForbidden` | `target` equals the vault address | Use a different recipient |
| `BadExpiry` | `expiry <= block.timestamp` | Increase `EXPIRY` to at least 120 seconds in the future |

### Agent Guidelines

> 1. Always set `EXPIRY` generously (at least several hours beyond `FIRE_AT`) to allow time for the keeper to observe and call `execute`.
> 2. Confirm `VALUE_WEI` covers the intended transfer plus gas. The vault escrows exactly `msg.value`.
> 3. Save the intent ID immediately after scheduling; it is needed for every subsequent operation on this intent.
> 4. A successful `cast send` does NOT mean the intent has settled — it only means it is registered. Settlement happens when `execute` is called later.

---

## Schedule a Balance-Triggered Intent {#schedule-balance}

Register an intent that becomes executable when a watched account's native PHRS balance crosses a
threshold (drops below or rises above). Useful for conditional payments, auto-rebalancing triggers,
or escrow release tied to on-chain balance state.

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__

# Inputs
TARGET=<recipient-or-contract>
SUBJECT=<account-whose-balance-is-watched>
THRESHOLD_WEI=<balance-threshold-in-wei>
EXPIRY=<unix-seconds>
VALUE_WEI=<wei-to-escrow>

# BALANCE_BELOW (cType=1): fires when subject.balance <= threshold
cast send "$VAULT" \
  "scheduleIntent(address,bytes,(uint8,address,uint256),uint64)" \
  "$TARGET" \
  "0x" \
  "(1,$SUBJECT,$THRESHOLD_WEI)" \
  "$EXPIRY" \
  --value "$VALUE_WEI" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"

# BALANCE_ABOVE (cType=2): fires when subject.balance >= threshold
cast send "$VAULT" \
  "scheduleIntent(address,bytes,(uint8,address,uint256),uint64)" \
  "$TARGET" \
  "0x" \
  "(2,$SUBJECT,$THRESHOLD_WEI)" \
  "$EXPIRY" \
  --value "$VALUE_WEI" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `target` | `address` | Recipient or contract on settlement |
| `data` | `bytes` | Calldata. Use `0x` for a native transfer. |
| `condition` tuple `cType` | `uint8` | `1` = BALANCE_BELOW, `2` = BALANCE_ABOVE |
| `condition` tuple `subject` | `address` | Account whose native balance is monitored |
| `condition` tuple `threshold` | `uint256` | Balance threshold in wei |
| `expiry` | `uint64` | Deadline in Unix seconds |
| `--value` | wei | PHRS to escrow |

### Output Parsing

Same as time-based: read `intentCount - 1` or parse `IntentScheduled` from the receipt.

```bash
ID=$(( $(cast call "$VAULT" "intentCount()(uint256)" --rpc-url "$RPC") - 1 ))
```

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `ZeroTarget` | `target` is the zero address | Provide a valid non-zero address |
| `BadExpiry` | `expiry <= block.timestamp` | Increase `EXPIRY` |
| `SelfCallForbidden` | `target` is the vault | Choose a different target |

### Agent Guidelines

> 1. For BALANCE_BELOW: the condition is `subject.balance <= threshold`. Confirm the current balance with `cast balance $SUBJECT --rpc-url $RPC` before scheduling so the threshold is meaningful.
> 2. For BALANCE_ABOVE: the condition is `subject.balance >= threshold`. Useful for "top-up detected" triggers.
> 3. The vault reads native (PHRS) balance only. ERC-20 balances are not readable in v1.
> 4. Keep the expiry realistic for the expected time to condition-hit. If the balance threshold is unlikely to be hit within the expiry window, the intent will expire unsettled.

---

## Check if an Intent is Ready {#can-execute}

Read whether an intent is Active, not yet expired, and has its condition satisfied. Use this as the
keeper poll gate before attempting `execute`.

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__
ID=<intent-id>

cast call "$VAULT" "canExecute(uint256)(bool)" "$ID" --rpc-url "$RPC"
# Returns: true or false
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `id` | `uint256` | Intent ID returned at schedule time |

### Output Parsing

`cast call` returns `true` or `false` as a plain string.

```bash
READY=$(cast call "$VAULT" "canExecute(uint256)(bool)" "$ID" --rpc-url "$RPC")
if [ "$READY" = "true" ]; then
  echo "Ready to execute"
else
  echo "Not ready yet"
fi
```

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `IntentNotFound` | `id >= intentCount` | Read `intentCount` first; IDs are zero-indexed sequential integers |

### Agent Guidelines

> 1. Poll `canExecute` at a frequency appropriate to the condition type. For TIME conditions, polling every 10-30 seconds near the threshold timestamp is sufficient. For BALANCE conditions, poll at a cadence that matches expected balance change frequency.
> 2. A `false` return from `canExecute` is never an error. It means the condition is not yet satisfied or the intent is already settled.
> 3. `canExecute` returning `false` because the intent is already Executed/Cancelled/Reclaimed produces `false`, not a revert. Check `getIntent` status if you need to distinguish these cases.
> 4. If `canExecute` reverts with `IntentNotFound`, the ID is invalid. Verify it against `intentCount`.

---

## Execute a Ready Intent {#execute}

Settle an intent that `canExecute` returns `true` for. Permissionless — any address may call this.
The vault transfers the escrowed PHRS to `target` (with `data` as calldata) and marks the intent
as Executed.

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__
ID=<intent-id>

cast send "$VAULT" "execute(uint256)" "$ID" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"
```

Gas is paid by the executor. The escrowed PHRS goes to the intent's `target`, not the executor.

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `id` | `uint256` | Intent ID to settle |

### Output Parsing

A successful execution emits `IntentExecuted(uint256 indexed id, address indexed executor)`.

```bash
# Confirm final status via getIntent after the tx
cast call "$VAULT" "getIntent(uint256)" "$ID" --rpc-url "$RPC"
# status field: 0=Active, 1=Executed, 2=Cancelled, 3=Reclaimed
```

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `IntentNotFound` | `id >= intentCount` | Verify the ID |
| `NotActive` | Already settled (Executed/Cancelled/Reclaimed) | No action needed; intent is done |
| `Expired` | `block.timestamp > expiry` | Intent window closed. The owner can call `reclaim` |
| `ConditionNotMet` | Condition is valid but not satisfied right now | Wait; poll `canExecute` and retry when it returns `true` |
| `CallFailed` | The target call reverted | Inspect the target contract; the intent remains Active and may be retried or cancelled |

### Agent Guidelines

> 1. Always call `canExecute` immediately before `cast send execute`. On-chain state may have changed between your poll and your transaction landing.
> 2. `ConditionNotMet` is a transient rejection, not a permanent failure. Retry after the condition changes.
> 3. `CallFailed` leaves the intent in Active status. The owner may cancel it or you may retry execute once the target is fixed.
> 4. The executor pays gas but receives no PHRS reward in v1. Keeper incentive design is out of scope for this contract.

---

## Cancel Before Settlement / Reclaim After Expiry {#cancel-reclaim}

Two owner-only paths for recovering escrowed PHRS when an intent should not settle:

- `cancel`: cancels an Active intent before it is executed (owner can call at any time while Active, regardless of expiry).
- `reclaim`: recovers escrow after the intent has passed its expiry without settling (only callable after `block.timestamp > expiry`).

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__
ID=<intent-id>

# Cancel an Active intent (anytime while Active, owner only)
cast send "$VAULT" "cancel(uint256)" "$ID" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"

# Reclaim escrow after expiry (only after expiry, owner only)
cast send "$VAULT" "reclaim(uint256)" "$ID" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY"
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `id` | `uint256` | Intent ID to cancel or reclaim |

### Output Parsing

- `cancel` emits `IntentCancelled(uint256 indexed id)`.
- `reclaim` emits `IntentReclaimed(uint256 indexed id)`.

Both refund the escrowed PHRS to the caller (intent owner) as a native transfer.

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `IntentNotFound` | `id >= intentCount` | Verify the ID |
| `NotOwner` | Caller is not the intent's owner | Only the scheduling address can cancel or reclaim |
| `NotActive` | Intent is already settled | No action; escrow already released |
| `NotExpired` | `reclaim` called before `block.timestamp > expiry` | Wait until after expiry, then retry `reclaim` |

### Agent Guidelines

> 1. Use `cancel` when you want to abort an Active intent before it can be executed by any keeper.
> 2. Use `reclaim` only after the expiry timestamp has passed and the intent was never executed. Check current time vs expiry with `cast block latest --rpc-url $RPC` (look at the `timestamp` field).
> 3. Both operations fully restore the escrowed PHRS to the owner's wallet.
> 4. An intent cannot be both cancelled and reclaimed. Once status is Cancelled, `reclaim` reverts with `NotActive`.

---

## Read an Intent's State {#read-intent}

Inspect the full on-chain state of any intent by ID. No wallet required.

### Command Template

```bash
RPC=https://atlantic.dplabs-internal.com
VAULT=__VAULT_ADDRESS__
ID=<intent-id>

# Read full intent struct
cast call "$VAULT" "getIntent(uint256)" "$ID" --rpc-url "$RPC"

# Read global counters
cast call "$VAULT" "intentCount()(uint256)" --rpc-url "$RPC"
cast call "$VAULT" "totalEscrowed()(uint256)" --rpc-url "$RPC"
```

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `id` | `uint256` | Intent ID (0-indexed; valid range is 0 to `intentCount - 1`) |

### Output Parsing

`getIntent` returns the ABI-encoded `Intent` struct. Fields in order:

| Field | Type | Values |
|---|---|---|
| `owner` | `address` | Address that called `scheduleIntent` |
| `target` | `address` | Recipient or contract on settlement |
| `value` | `uint256` | Escrowed PHRS in wei |
| `expiry` | `uint64` | Deadline in Unix seconds |
| `status` | `uint8` | `0`=Active, `1`=Executed, `2`=Cancelled, `3`=Reclaimed |
| `condition.cType` | `uint8` | `0`=TIME, `1`=BALANCE_BELOW, `2`=BALANCE_ABOVE |
| `condition.subject` | `address` | Watched account (BALANCE_*) or zero address (TIME) |
| `condition.threshold` | `uint256` | Timestamp (TIME) or wei threshold (BALANCE_*) |
| `data` | `bytes` | Calldata for target; `0x` for plain transfers |

`totalEscrowed` is the sum of all Active intent escrows. The vault's native balance always satisfies `balance >= totalEscrowed`.

### Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `IntentNotFound` | `id >= intentCount` | Read `intentCount` first to find the valid range |

### Agent Guidelines

> 1. Read `intentCount` before reading any intent to confirm the ID is in range.
> 2. Cross-check `status` before calling `execute`, `cancel`, or `reclaim` to avoid unnecessary gas spend on a reverted transaction.
> 3. `totalEscrowed` provides a solvency view: it should always be at or below the contract's native balance. A discrepancy indicates a critical invariant violation.
> 4. `data` is returned ABI-encoded. For plain PHRS transfers it decodes as empty (`0x`).
