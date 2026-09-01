// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IStakingModule} from "../../src/interfaces/IStakingModule.sol";

contract StakingModuleMock {
    address public accountingAddress;

    IStakingModule.NodeOperator[] internal _operators;

    constructor(address accounting_) {
        accountingAddress = accounting_;
    }

    // solhint-disable-next-line func-name-mixedcase
    function ACCOUNTING() external view returns (address) {
        return accountingAddress;
    }

    function setAccounting(address accounting_) external {
        accountingAddress = accounting_;
    }

    function addOperator(address managerAddress, address rewardAddress, bool extendedManagerPermissions)
        external
        returns (uint256 id)
    {
        id = _operators.length;
        _operators.push();
        IStakingModule.NodeOperator storage no = _operators[id];
        no.managerAddress = managerAddress;
        no.rewardAddress = rewardAddress;
        no.extendedManagerPermissions = extendedManagerPermissions;
    }

    function setProposedAddresses(uint256 nodeOperatorId, address proposedManagerAddress, address proposedRewardAddress)
        external
    {
        IStakingModule.NodeOperator storage no = _operators[nodeOperatorId];
        no.proposedManagerAddress = proposedManagerAddress;
        no.proposedRewardAddress = proposedRewardAddress;
    }

    function getNodeOperatorsCount() external view returns (uint256) {
        return _operators.length;
    }

    function getNodeOperator(uint256 nodeOperatorId) external view returns (IStakingModule.NodeOperator memory) {
        return _operators[nodeOperatorId];
    }

    function getNodeOperatorManagementProperties(uint256 nodeOperatorId)
        external
        view
        returns (IStakingModule.NodeOperatorManagementProperties memory)
    {
        IStakingModule.NodeOperator storage no = _operators[nodeOperatorId];
        return IStakingModule.NodeOperatorManagementProperties({
            managerAddress: no.managerAddress,
            rewardAddress: no.rewardAddress,
            extendedManagerPermissions: no.extendedManagerPermissions
        });
    }
}
