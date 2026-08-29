// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {UpgradeHoodi} from "../script/UpgradeHoodi.s.sol";
import {UpgradeBase} from "../script/UpgradeBase.s.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";

contract UpgradeScriptTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    address internal constant STAKING_ROUTER =
        0xCc820558B39ee15C7C45B59390B503b83fb499A8;

    OssifiableProxy internal proxy;
    address internal firstImplementation;

    function setUp() external {
        vm.chainId(HOODI_CHAIN_ID);
        vm.etch(STAKING_ROUTER, address(new StakingRouterMock()).code);

        firstImplementation = address(new SMDiscovery(STAKING_ROUTER));
        proxy = new OssifiableProxy(
            firstImplementation,
            address(this),
            ""
        );
    }

    /// @dev All three cases share one test function on purpose: `vm.setEnv` mutates
    ///      process-global state and forge runs tests in parallel, so exactly one test
    ///      function may own `PROXY_ADDRESS`. Splitting these reintroduces a real race.
    function test_upgrade_adminUpgradesNonAdminDefersUnsetReverts() external {
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(proxy)));

        // 1. The test contract is both the proxy admin and run()'s caller, so
        //    UpgradeBase's `broadcaster == admin` branch runs and the upgrade lands.
        UpgradeHoodi adminRun = new UpgradeHoodi();
        adminRun.run();

        address upgraded = address(adminRun.implementation());
        assertEq(proxy.proxy__getImplementation(), upgraded);
        assertTrue(upgraded != firstImplementation, "implementation unchanged");

        // 2. Under a different admin the script still deploys an implementation,
        //    but must leave the proxy pointing where it was.
        proxy.proxy__changeAdmin(address(0xBEEF));

        UpgradeHoodi nonAdminRun = new UpgradeHoodi();
        nonAdminRun.run();

        assertEq(proxy.proxy__getImplementation(), upgraded);
        assertTrue(
            address(nonAdminRun.implementation()) != upgraded,
            "expected a freshly deployed implementation"
        );

        // 3. An ossified proxy must revert before deploying anything.
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(proxy)));
        vm.prank(address(0xBEEF));
        proxy.proxy__ossify();

        UpgradeHoodi ossifiedRun = new UpgradeHoodi();
        vm.expectRevert(UpgradeBase.ProxyIsOssified.selector);
        ossifiedRun.run();

        // 4. An unset PROXY_ADDRESS must revert before anything is broadcast.
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(0)));

        UpgradeHoodi unsetRun = new UpgradeHoodi();
        vm.expectRevert(UpgradeBase.ProxyAddressNotSet.selector);
        unsetRun.run();
    }
}
