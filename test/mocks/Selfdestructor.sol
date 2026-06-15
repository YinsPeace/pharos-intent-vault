// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Force-feeds native value to a target via selfdestruct, bypassing the absence of a
///      receive()/fallback() on the target. Used to test that forced ether cannot break solvency.
contract Selfdestructor {
    constructor() payable {}

    function boom(address payable to) external {
        selfdestruct(to);
    }
}
