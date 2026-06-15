// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
contract Reverter { receive() external payable { revert("no"); } }
