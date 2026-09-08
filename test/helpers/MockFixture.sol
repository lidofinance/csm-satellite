// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import "../../src/SMDiscovery.sol";
import {StakingRouterMock} from "../mocks/StakingRouterMock.sol";
import {StakingModuleMock} from "../mocks/StakingModuleMock.sol";
import {AccountingMock} from "../mocks/AccountingMock.sol";

/// @dev Shared router + accounting + module + discovery wiring for local-mock tests
abstract contract MockFixture is Test {
    uint256 internal constant MODULE_ID = 3;

    StakingRouterMock internal router;
    StakingModuleMock internal module;
    AccountingMock internal accounting;
    SMDiscovery internal discovery;

    function setUp() external {
        router = new StakingRouterMock();
        accounting = new AccountingMock();
        module = new StakingModuleMock(address(accounting));
        router.setModule(MODULE_ID, address(module));

        discovery = new SMDiscovery(address(router));
        discovery.updateModuleCache(MODULE_ID);
    }
}
