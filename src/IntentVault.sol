// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IntentVault
/// @notice Register condition-gated, pre-funded on-chain intents; an executor settles each only if valid.
/// @author YinsPeace
contract IntentVault {
    enum ConditionType { TIME, BALANCE_BELOW, BALANCE_ABOVE }
    enum Status { Active, Executed, Cancelled, Reclaimed }

    struct Condition {
        ConditionType cType;
        address subject;   // BALANCE_*: watched account; TIME: unused
        uint256 threshold; // TIME: unix seconds; BALANCE_*: wei
    }

    struct Intent {
        address owner;
        address target;
        uint256 value;     // escrowed PHRS for THIS intent
        uint64 expiry;
        Status status;
        Condition condition;
        bytes data;
    }

    uint256 public intentCount;
    uint256 public totalEscrowed; // sum of Active escrows; solvency: balance >= totalEscrowed
    mapping(uint256 => Intent) private _intents;

    event IntentScheduled(uint256 indexed id, address indexed owner, address indexed target, uint256 value, uint64 expiry);

    error ZeroTarget();
    error SelfCallForbidden();
    error BadExpiry();
    error IntentNotFound();

    function scheduleIntent(
        address target,
        bytes calldata data,
        Condition calldata condition,
        uint64 expiry
    ) external payable returns (uint256 id) {
        if (target == address(0)) revert ZeroTarget();
        if (target == address(this)) revert SelfCallForbidden();
        if (expiry <= block.timestamp) revert BadExpiry();

        id = intentCount++;
        _intents[id] = Intent({
            owner: msg.sender,
            target: target,
            value: msg.value,
            expiry: expiry,
            status: Status.Active,
            condition: condition,
            data: data
        });
        totalEscrowed += msg.value;
        emit IntentScheduled(id, msg.sender, target, msg.value, expiry);
    }

    function getIntent(uint256 id) external view returns (Intent memory) {
        if (id >= intentCount) revert IntentNotFound();
        return _intents[id];
    }
}
