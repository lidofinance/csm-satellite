// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IAccounting} from "../../src/interfaces/IAccounting.sol";

contract AccountingMock {
    mapping(uint256 => uint256) internal _bondCurveId;
    mapping(uint256 => IAccounting.BondLockData) internal _lockedBondInfo;
    mapping(uint256 => address) internal _customRewardsClaimer;

    function setBondCurveId(uint256 nodeOperatorId, uint256 curveId) external {
        _bondCurveId[nodeOperatorId] = curveId;
    }

    function getBondCurveId(uint256 nodeOperatorId) external view returns (uint256) {
        return _bondCurveId[nodeOperatorId];
    }

    function setLockedBondInfo(uint256 nodeOperatorId, uint128 amount, uint128 until) external {
        _lockedBondInfo[nodeOperatorId] = IAccounting.BondLockData({amount: amount, until: until});
    }

    function getLockedBondInfo(uint256 nodeOperatorId) external view returns (IAccounting.BondLockData memory) {
        return _lockedBondInfo[nodeOperatorId];
    }

    function setCustomRewardsClaimer(uint256 nodeOperatorId, address claimer) external {
        _customRewardsClaimer[nodeOperatorId] = claimer;
    }

    function getCustomRewardsClaimer(uint256 nodeOperatorId) external view returns (address) {
        return _customRewardsClaimer[nodeOperatorId];
    }
}
