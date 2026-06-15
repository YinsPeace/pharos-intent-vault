// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
contract ReturnBomber {
    bool public hit;
    fallback() external payable { hit = true; assembly { return(0, 100000) } } // returns ~100KB
    receive() external payable { hit = true; }
}
