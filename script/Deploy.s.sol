// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {IntentVault} from "../src/IntentVault.sol";

/// @notice Deploys IntentVault to Pharos Atlantic Testnet. Reads PRIVATE_KEY from the environment.
contract Deploy is Script {
    function run() external returns (IntentVault vault) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        vault = new IntentVault();
        vm.stopBroadcast();
    }
}
