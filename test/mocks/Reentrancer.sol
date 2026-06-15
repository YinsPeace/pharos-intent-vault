// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {IntentVault} from "../../src/IntentVault.sol";
contract Reentrancer {
    IntentVault public vault;
    uint256 public targetId;
    constructor(IntentVault v) { vault = v; }
    function arm(uint256 id) external { targetId = id; }
    receive() external payable {
        // attempt to re-enter execute on another intent during settlement
        try vault.execute(targetId) {} catch {}
    }
}
