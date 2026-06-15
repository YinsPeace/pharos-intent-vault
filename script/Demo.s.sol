// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IntentVault} from "../src/IntentVault.sol";

/// @notice End-to-end demo against the live Atlantic deployment: schedule a time-gated intent
///         that is immediately executable, then settle it. Run with:
///         forge script script/Demo.s.sol:Demo --rpc-url https://atlantic.dplabs-internal.com --broadcast
contract Demo is Script {
    IntentVault constant VAULT = IntentVault(0x10f1d2a0B6A60ec8A872fbe46a909021EDd7a217);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);

        // Schedule a TIME intent that is already due (threshold = now), escrowing 0.001 PHRS,
        // paying it back to `me` on settlement, with a 1-hour expiry window.
        uint256 id = VAULT.scheduleIntent{value: 0.001 ether}(
            me,
            "",
            IntentVault.Condition(IntentVault.ConditionType.TIME, address(0), block.timestamp),
            uint64(block.timestamp + 3600)
        );
        console.log("scheduled intent id:", id);

        // Settle it (permissionless; here the same account acts as the keeper).
        VAULT.execute(id);
        console.log("executed intent id:", id);

        vm.stopBroadcast();
    }
}
