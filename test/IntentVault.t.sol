// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IntentVault} from "../src/IntentVault.sol";

contract IntentVaultTest is Test {
    IntentVault vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vault = new IntentVault();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _timeCond(uint256 ts) internal pure returns (IntentVault.Condition memory) {
        return IntentVault.Condition(IntentVault.ConditionType.TIME, address(0), ts);
    }

    function test_canExecute_time() public {
        uint256 fireAt = block.timestamp + 1 days;
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _timeCond(fireAt), uint64(block.timestamp + 2 days)
        );
        assertFalse(vault.canExecute(id));      // before fireAt
        vm.warp(fireAt);
        assertTrue(vault.canExecute(id));       // at/after fireAt
    }

    function test_scheduleIntent_storesAndEscrows() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _timeCond(block.timestamp + 1 days), uint64(block.timestamp + 2 days)
        );
        assertEq(id, 0);
        assertEq(vault.intentCount(), 1);
        assertEq(vault.totalEscrowed(), 1 ether);
        assertEq(address(vault).balance, 1 ether);

        IntentVault.Intent memory it = vault.getIntent(0);
        assertEq(it.owner, alice);
        assertEq(it.target, bob);
        assertEq(it.value, 1 ether);
        assertEq(uint8(it.status), uint8(IntentVault.Status.Active));
    }
}
