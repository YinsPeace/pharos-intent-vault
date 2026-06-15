// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IntentVault} from "../src/IntentVault.sol";

contract Handler is Test {
    IntentVault public vault;
    constructor(IntentVault v) { vault = v; vm.deal(address(this), 1_000 ether); }

    function schedule(uint96 value, uint64 dt) external {
        value = uint96(bound(value, 0, 10 ether));
        uint256 exp = block.timestamp + bound(dt, 1, 30 days);
        try vault.scheduleIntent{value: value}(
            address(0xBEEF), "", IntentVault.Condition(IntentVault.ConditionType.TIME, address(0), block.timestamp),
            uint64(exp)
        ) {} catch {}
    }
    function exec(uint256 id) external { try vault.execute(id % (vault.intentCount() + 1)) {} catch {} }
    function cancelAny(uint256 id) external { try vault.cancel(id % (vault.intentCount() + 1)) {} catch {} }

    receive() external payable {}
}

contract IntentVaultInvariant is Test {
    IntentVault vault;
    Handler handler;

    function setUp() public {
        vault = new IntentVault();
        handler = new Handler(vault);
        targetContract(address(handler));
    }

    /// @dev The vault is always solvent: it holds at least the funds it still owes.
    function invariant_solvency() public view {
        assertGe(address(vault).balance, vault.totalEscrowed());
    }
}
