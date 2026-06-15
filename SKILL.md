---
name: pharos-intent-vault
description: >
  Schedule conditional on-chain intents on Pharos Atlantic: time-lock, balance-trigger, and
  arbitrary escrow automation. An agent registers an intent (optionally with escrowed PHRS),
  then a permissionless keeper/executor calls execute once the condition is met. Covers: intent
  scheduling, conditional execution, time-lock, balance-trigger, agent automation, escrow,
  reclaim, and cancel workflows on the IntentVault contract.
version: 0.1.0
requires:
  anyBins:
  - cast
  - forge
---

# Pharos IntentVault Skill

Condition-gated, pre-funded on-chain execution primitive for AI agents on Pharos Atlantic.

## Prerequisites

Install Foundry (includes `cast` and `forge`):

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Set your private key before any write operation:

```bash
export PRIVATE_KEY=0x<your-key>
export VAULT=0x10f1d2a0B6A60ec8A872fbe46a909021EDd7a217
```

`PRIVATE_KEY` must never be committed to source control or logged. Store it in a secrets manager or shell session variable only.

## Network Configuration

The skill reads network parameters from `assets/networks.json`. Atlantic testnet is the default.

```json
{
  "networks": [
    {
      "name": "atlantic-testnet",
      "rpcUrl": "https://atlantic.dplabs-internal.com",
      "chainId": 688689,
      "explorerUrl": "https://atlantic.pharosscan.xyz/",
      "nativeToken": "PHRS"
    }
  ],
  "defaultNetwork": "atlantic-testnet"
}
```

Inject the RPC URL in every `cast` call:

```bash
RPC=https://atlantic.dplabs-internal.com
cast call "$VAULT" "intentCount()(uint256)" --rpc-url $RPC
```

## Capability Index

| User Need | Capability | Detailed Instructions |
|---|---|---|
| Schedule an action to fire at a future timestamp | Time-based intent | → [references/intent-vault.md#schedule-time](references/intent-vault.md#schedule-time) |
| Schedule an action when a wallet balance crosses a threshold | Balance-triggered intent | → [references/intent-vault.md#schedule-balance](references/intent-vault.md#schedule-balance) |
| Check whether an intent is ready to settle | Readiness check | → [references/intent-vault.md#can-execute](references/intent-vault.md#can-execute) |
| Settle a ready intent (keeper/executor role) | Execute intent | → [references/intent-vault.md#execute](references/intent-vault.md#execute) |
| Cancel an Active intent (owner only) or reclaim escrowed funds after expiry | Cancel / Reclaim | → [references/intent-vault.md#cancel-reclaim](references/intent-vault.md#cancel-reclaim) |
| Read an intent's full on-chain state | Inspect intent | → [references/intent-vault.md#read-intent](references/intent-vault.md#read-intent) |

## General Error Handling

| Error | Cause | Agent Action |
|---|---|---|
| `ZeroTarget` | `target` address is `0x0000...` | Supply a valid non-zero recipient or contract address |
| `SelfCallForbidden` | `target` is the vault itself | Use a different target; the vault cannot call itself |
| `BadExpiry` | `expiry` is at or before current block time | Set `expiry` to at least `$(date +%s) + 120` (2 min buffer) |
| `IntentNotFound` | `id` is greater than or equal to `intentCount` | Read `intentCount` first; IDs are zero-indexed |
| `NotActive` | Intent is already Executed, Cancelled, or Reclaimed | No action; intent is settled. Read its status with `getIntent` |
| `Expired` | `block.timestamp > expiry` at the moment of `execute` | Intent window closed. Owner may call `reclaim` to recover escrow |
| `ConditionNotMet` | Condition is valid but not yet satisfied | WAIT and retry. This is not an error state — poll `canExecute` |
| `CallFailed` | The target call reverted (e.g. insufficient gas, bad calldata) | Inspect target contract; confirm calldata and value are correct |
| `Reentrancy` | Nested call into the vault during execution | Vault is guarded; this indicates a bug in the executor caller |
| `NotOwner` | Caller is not the intent owner | Only the original `msg.sender` from `scheduleIntent` may cancel or reclaim |
| `NotExpired` | `reclaim` called before expiry | Wait until `block.timestamp > expiry`, then retry `reclaim` |

## Security Reminders

- `PRIVATE_KEY` must be set only in the current shell session. Never hardcode it in scripts or pass it via environment files committed to git.
- Each intent's escrow is tracked independently in `totalEscrowed`. The vault's native balance always satisfies `balance >= totalEscrowed` by invariant.
- Use isolated wallets for keeper/executor operations. The `execute` function is permissionless — any address may call it.
- Do not reuse intent IDs. IDs are assigned sequentially by the contract and are permanent.

## Write Operation Pre-checks

Run these checks in order before any state-changing call:

1. Confirm `PRIVATE_KEY` is set:

```bash
: "${PRIVATE_KEY:?PRIVATE_KEY is not set}"
```

2. Derive your address and confirm it is the intended sender:

```bash
cast wallet address --private-key "$PRIVATE_KEY"
```

3. Confirm you are targeting Atlantic testnet (chain ID 688689):

```bash
cast chain-id --rpc-url https://atlantic.dplabs-internal.com
# expected: 688689
```

4. Check your PHRS balance is sufficient for the escrowed value plus gas:

```bash
cast balance $(cast wallet address --private-key "$PRIVATE_KEY") \
  --rpc-url https://atlantic.dplabs-internal.com
```
