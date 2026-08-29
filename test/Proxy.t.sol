// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";
import {StakingModuleMock} from "./mocks/StakingModuleMock.sol";
import {SMDiscoveryV2Mock} from "./mocks/SMDiscoveryV2Mock.sol";

contract ProxyTest is Test {
    uint256 internal constant MODULE_ID = 3;
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ACCOUNTING = address(0xACC0);

    StakingRouterMock internal router;
    StakingModuleMock internal module;
    SMDiscovery internal implementation;
    OssifiableProxy internal proxy;
    SMDiscovery internal discovery;

    function setUp() public {
        router = new StakingRouterMock();
        module = new StakingModuleMock(ACCOUNTING);
        router.setModule(MODULE_ID, address(module));

        implementation = new SMDiscovery(address(router));
        proxy = new OssifiableProxy(address(implementation), ADMIN, "");
        discovery = SMDiscovery(address(proxy));
    }

    function test_immutableStakingRouter_resolvesThroughDelegatecall()
        external
        view
    {
        assertEq(address(discovery.STAKING_ROUTER()), address(router));
    }

    function test_proxy_reportsAdminAndImplementation() external view {
        assertEq(proxy.proxy__getAdmin(), ADMIN);
        assertEq(proxy.proxy__getImplementation(), address(implementation));
        assertFalse(proxy.proxy__getIsOssified());
    }

    function test_updateModuleCache_writesThroughProxy() external {
        discovery.updateModuleCache(MODULE_ID);
        (address moduleAddress, address accountingAddress) = discovery
            .moduleCache(MODULE_ID);
        assertEq(moduleAddress, address(module));
        assertEq(accountingAddress, ACCOUNTING);
    }

    function test_upgrade_preservesModuleCache() external {
        discovery.updateModuleCache(MODULE_ID);
        (address moduleBefore, address accountingBefore) = discovery
            .moduleCache(MODULE_ID);

        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(ADMIN);
        proxy.proxy__upgradeTo(address(v2));

        (address moduleAfter, address accountingAfter) = discovery.moduleCache(
            MODULE_ID
        );
        assertEq(moduleAfter, moduleBefore);
        assertEq(accountingAfter, accountingBefore);
        assertEq(proxy.proxy__getImplementation(), address(v2));
        assertEq(SMDiscoveryV2Mock(address(proxy)).VERSION(), 2);
    }

    function test_upgrade_revertsForNonAdmin() external {
        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(address(0xBEEF));
        vm.expectRevert(OssifiableProxy.NotAdmin.selector);
        proxy.proxy__upgradeTo(address(v2));
    }

    function test_ossify_blocksFurtherUpgrades() external {
        vm.prank(ADMIN);
        proxy.proxy__ossify();
        assertTrue(proxy.proxy__getIsOssified());
        assertEq(proxy.proxy__getAdmin(), address(0));

        SMDiscoveryV2Mock v2 = new SMDiscoveryV2Mock(address(router));
        vm.prank(ADMIN);
        vm.expectRevert(OssifiableProxy.ProxyIsOssified.selector);
        proxy.proxy__upgradeTo(address(v2));
    }

    function test_ossify_revertsForNonAdmin() external {
        vm.prank(address(0xBEEF));
        vm.expectRevert(OssifiableProxy.NotAdmin.selector);
        proxy.proxy__ossify();
    }

    function test_ossifiedProxy_stillServesReads() external {
        discovery.updateModuleCache(MODULE_ID);
        vm.prank(ADMIN);
        proxy.proxy__ossify();
        assertEq(address(discovery.STAKING_ROUTER()), address(router));
        (address moduleAddress, ) = discovery.moduleCache(MODULE_ID);
        assertEq(moduleAddress, address(module));
    }
}
