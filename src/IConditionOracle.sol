// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IConditionOracle
/// @notice Phase-2 extension point. A future PRICE ConditionType would read an oracle implementing
///         this interface to decide whether an intent is executable. NOT wired in v1 (no live feed
///         dependency on the Phase-1 clock); shipped as a documented interface + mock.
interface IConditionOracle {
    /// @return met True if the oracle-defined condition currently holds.
    function isMet(bytes calldata params) external view returns (bool met);
}
