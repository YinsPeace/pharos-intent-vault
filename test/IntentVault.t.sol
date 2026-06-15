// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IntentVault} from "../src/IntentVault.sol";
import {Reverter} from "./mocks/Reverter.sol";
import {Receiver} from "./mocks/Receiver.sol";
import {Reentrancer} from "./mocks/Reentrancer.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {IConditionOracle} from "../src/IConditionOracle.sol";

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

    function test_execute_time_paysTargetOnce() public {
        uint256 fireAt = block.timestamp + 1 days;
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 3 ether}(
            bob, "", _timeCond(fireAt), uint64(block.timestamp + 2 days)
        );
        vm.warp(fireAt);

        uint256 bobBefore = bob.balance;
        vault.execute(id); // permissionless; called by test (any executor)
        assertEq(bob.balance, bobBefore + 3 ether);
        assertEq(vault.totalEscrowed(), 0);
        assertEq(address(vault).balance, 0);
        assertEq(uint8(vault.getIntent(id).status), uint8(IntentVault.Status.Executed));

        vm.expectRevert(IntentVault.NotActive.selector);
        vault.execute(id); // cannot run twice
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

    // --- Task 5: balance-threshold conditions ---

    function _balCond(IntentVault.ConditionType t, address who, uint256 thr)
        internal pure returns (IntentVault.Condition memory)
    {
        return IntentVault.Condition(t, who, thr);
    }

    function test_canExecute_balanceBelow() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _balCond(IntentVault.ConditionType.BALANCE_BELOW, bob, 50 ether),
            uint64(block.timestamp + 1 days)
        );
        assertFalse(vault.canExecute(id));   // bob has 100 ether
        // drain bob to 40 ether via vm.deal so no transfer target needed
        vm.deal(bob, 40 ether);
        assertTrue(vault.canExecute(id));    // 40 <= 50
    }

    function test_canExecute_balanceAbove() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _balCond(IntentVault.ConditionType.BALANCE_ABOVE, bob, 150 ether),
            uint64(block.timestamp + 1 days)
        );
        assertFalse(vault.canExecute(id));   // 100 < 150
        vm.deal(bob, 200 ether);
        assertTrue(vault.canExecute(id));    // 200 >= 150
    }

    // --- Task 6: execute guards + schedule validation ---

    function test_execute_revertsWhenConditionNotMet() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _timeCond(block.timestamp + 1 days), uint64(block.timestamp + 2 days)
        );
        vm.expectRevert(IntentVault.ConditionNotMet.selector);
        vault.execute(id);
    }

    function test_execute_revertsWhenExpired() public {
        uint256 fireAt = block.timestamp + 1 days;
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _timeCond(fireAt), uint64(fireAt + 1)
        );
        vm.warp(fireAt + 2); // past expiry
        vm.expectRevert(IntentVault.Expired.selector);
        vault.execute(id);
    }

    function test_execute_revertsUnknownId() public {
        vm.expectRevert(IntentVault.IntentNotFound.selector);
        vault.execute(99);
    }

    function test_schedule_rejectsBadArgs() public {
        vm.startPrank(alice);
        vm.expectRevert(IntentVault.ZeroTarget.selector);
        vault.scheduleIntent{value: 1 ether}(address(0), "", _timeCond(block.timestamp+1), uint64(block.timestamp+2));
        vm.expectRevert(IntentVault.SelfCallForbidden.selector);
        vault.scheduleIntent{value: 1 ether}(address(vault), "", _timeCond(block.timestamp+1), uint64(block.timestamp+2));
        vm.expectRevert(IntentVault.BadExpiry.selector);
        vault.scheduleIntent{value: 1 ether}(bob, "", _timeCond(block.timestamp+1), uint64(block.timestamp));
        vm.stopPrank();
    }

    // --- Task 7: cancel ---

    function test_cancel_refundsOwner() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 2 ether}(
            bob, "", _timeCond(block.timestamp + 1 days), uint64(block.timestamp + 2 days)
        );
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        vault.cancel(id);
        assertEq(alice.balance, aliceBefore + 2 ether);
        assertEq(vault.totalEscrowed(), 0);
        assertEq(uint8(vault.getIntent(id).status), uint8(IntentVault.Status.Cancelled));
    }

    function test_cancel_onlyOwner() public {
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(
            bob, "", _timeCond(block.timestamp + 1 days), uint64(block.timestamp + 2 days)
        );
        vm.prank(bob);
        vm.expectRevert(IntentVault.NotOwner.selector);
        vault.cancel(id);
    }

    // --- Task 8: reclaim ---

    // --- Task 9: reentrancy + CallFailed + isolation ---

    function test_execute_revertsOnTargetFailure_keepsEscrow() public {
        Reverter r = new Reverter();
        uint256 fireAt = block.timestamp + 1;
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 1 ether}(address(r), "", _timeCond(fireAt), uint64(fireAt + 1000));
        vm.warp(fireAt);
        vm.expectRevert(IntentVault.CallFailed.selector);
        vault.execute(id);
        // state unchanged: still Active, escrow intact, owner can reclaim later
        assertEq(uint8(vault.getIntent(id).status), uint8(IntentVault.Status.Active));
        assertEq(vault.totalEscrowed(), 1 ether);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_reentrancy_blocked_isolatesEscrow() public {
        Reentrancer atk = new Reentrancer(vault);
        Receiver good = new Receiver();
        uint256 fireAt = block.timestamp + 1;
        // intent A pays the attacker; intent B pays a good receiver
        vm.prank(alice);
        uint256 idA = vault.scheduleIntent{value: 1 ether}(address(atk), "", _timeCond(fireAt), uint64(fireAt + 1000));
        vm.prank(alice);
        uint256 idB = vault.scheduleIntent{value: 5 ether}(address(good), "", _timeCond(fireAt), uint64(fireAt + 1000));
        atk.arm(idB);
        vm.warp(fireAt);

        vault.execute(idA); // attacker re-enters execute(idB) inside receive; guard makes it a no-op
        // idA settled and paid its own 1 ether; idB untouched, escrow isolated
        assertEq(uint8(vault.getIntent(idA).status), uint8(IntentVault.Status.Executed));
        assertEq(uint8(vault.getIntent(idB).status), uint8(IntentVault.Status.Active));
        assertEq(vault.totalEscrowed(), 5 ether);
        assertEq(address(vault).balance, 5 ether);
    }

    function test_reclaim_afterExpiry() public {
        uint64 exp = uint64(block.timestamp + 1 days);
        vm.prank(alice);
        uint256 id = vault.scheduleIntent{value: 2 ether}(bob, "", _timeCond(block.timestamp + 12 hours), exp);

        vm.prank(alice);
        vm.expectRevert(IntentVault.NotExpired.selector);
        vault.reclaim(id); // too early

        vm.warp(exp + 1);
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        vault.reclaim(id);
        assertEq(alice.balance, aliceBefore + 2 ether);
        assertEq(vault.totalEscrowed(), 0);
        assertEq(uint8(vault.getIntent(id).status), uint8(IntentVault.Status.Reclaimed));
    }

    function test_oracleInterface_compilesAndToggles() public {
        MockOracle o = new MockOracle();
        assertFalse(IConditionOracle(address(o)).isMet(""));
        o.set(true);
        assertTrue(IConditionOracle(address(o)).isMet(""));
    }
}
