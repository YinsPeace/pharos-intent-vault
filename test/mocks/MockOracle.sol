// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {IConditionOracle} from "../../src/IConditionOracle.sol";
contract MockOracle is IConditionOracle {
    bool public flag;
    function set(bool v) external { flag = v; }
    function isMet(bytes calldata) external view returns (bool) { return flag; }
}
