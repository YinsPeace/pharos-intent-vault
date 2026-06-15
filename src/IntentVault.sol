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
    event IntentExecuted(uint256 indexed id, address indexed executor);
    event IntentCancelled(uint256 indexed id);
    event IntentReclaimed(uint256 indexed id);

    error ZeroTarget();
    error SelfCallForbidden();
    error BadExpiry();
    error IntentNotFound();
    error NotActive();
    error Expired();
    error ConditionNotMet();
    error CallFailed();
    error Reentrancy();
    error NotOwner();
    error NotExpired();

    bool private _locked;
    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

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

    function _conditionMet(Condition memory c) internal view returns (bool) {
        if (c.cType == ConditionType.TIME) {
            return block.timestamp >= c.threshold;
        } else if (c.cType == ConditionType.BALANCE_BELOW) {
            return c.subject.balance <= c.threshold;
        } else {
            return c.subject.balance >= c.threshold; // BALANCE_ABOVE
        }
    }

    function canExecute(uint256 id) public view returns (bool) {
        if (id >= intentCount) revert IntentNotFound();
        Intent storage it = _intents[id];
        if (it.status != Status.Active) return false;
        if (block.timestamp > it.expiry) return false;
        return _conditionMet(it.condition);
    }

    function execute(uint256 id) external nonReentrant {
        if (id >= intentCount) revert IntentNotFound();
        Intent storage it = _intents[id];
        if (it.status != Status.Active) revert NotActive();
        if (block.timestamp > it.expiry) revert Expired();
        if (!_conditionMet(it.condition)) revert ConditionNotMet();

        // effects
        it.status = Status.Executed;
        uint256 val = it.value;
        totalEscrowed -= val;
        address target = it.target;
        bytes memory data = it.data;

        // interaction
        (bool ok, ) = target.call{value: val}(data);
        if (!ok) revert CallFailed();

        emit IntentExecuted(id, msg.sender);
    }

    function cancel(uint256 id) external nonReentrant {
        if (id >= intentCount) revert IntentNotFound();
        Intent storage it = _intents[id];
        if (it.owner != msg.sender) revert NotOwner();
        if (it.status != Status.Active) revert NotActive();

        it.status = Status.Cancelled;
        uint256 val = it.value;
        totalEscrowed -= val;
        emit IntentCancelled(id);

        (bool ok, ) = msg.sender.call{value: val}("");
        if (!ok) revert CallFailed();
    }

    function reclaim(uint256 id) external nonReentrant {
        if (id >= intentCount) revert IntentNotFound();
        Intent storage it = _intents[id];
        if (it.owner != msg.sender) revert NotOwner();
        if (it.status != Status.Active) revert NotActive();
        if (block.timestamp <= it.expiry) revert NotExpired();

        it.status = Status.Reclaimed;
        uint256 val = it.value;
        totalEscrowed -= val;
        emit IntentReclaimed(id);

        (bool ok, ) = msg.sender.call{value: val}("");
        if (!ok) revert CallFailed();
    }
}
