// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployHoodi} from "../script/DeployHoodi.s.sol";
import {DeployBase} from "../script/DeployBase.s.sol";
import {SMDiscovery} from "../src/SMDiscovery.sol";

contract DeployScriptTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    uint256 internal constant HOODI_FORK_BLOCK = 3495000;
    uint256 internal constant CSM_MODULE_ID = 4;
    address internal constant PROXY_ADMIN = address(0xA11CE);

    function setUp() external {
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcUrl, HOODI_FORK_BLOCK);
        if (block.chainid != HOODI_CHAIN_ID) {
            vm.skip(true);
            return;
        }
    }

    /// @dev Both cases live in one test because vm.setEnv mutates process-global state and forge
    ///      runs tests in parallel; exactly one test function may own PROXY_ADMIN.
    function test_deploy_putsDiscoveryBehindProxyAndRequiresAdmin() external {
        vm.setEnv("PROXY_ADMIN", vm.toString(PROXY_ADMIN));

        DeployHoodi script = new DeployHoodi();
        script.run();

        assertEq(script.proxy().proxy__getAdmin(), PROXY_ADMIN);
        assertEq(
            script.proxy().proxy__getImplementation(),
            address(script.implementation())
        );
        assertEq(address(script.discovery()), address(script.proxy()));

        (address moduleAddress, ) = script.discovery().moduleCache(
            CSM_MODULE_ID
        );
        assertTrue(moduleAddress != address(0), "cache not seeded");

        vm.setEnv("PROXY_ADMIN", vm.toString(address(0)));

        DeployHoodi unsetScript = new DeployHoodi();
        vm.expectRevert(DeployBase.ProxyAdminNotSet.selector);
        unsetScript.run();
    }
}
