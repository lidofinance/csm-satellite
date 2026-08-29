// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

contract StakingModuleMock {
    address public accountingAddress;

    constructor(address accounting_) {
        accountingAddress = accounting_;
    }

    // solhint-disable-next-line func-name-mixedcase
    function ACCOUNTING() external view returns (address) {
        return accountingAddress;
    }
}
