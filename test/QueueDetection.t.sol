// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import "../src/SMDiscovery.sol";
import {Batch} from "../src/interfaces/IBatch.sol";
import {OssifiableProxy} from "../src/lib/proxy/OssifiableProxy.sol";

/// @dev Regression test for the CSM queue-detection probe (see _tryGetMaxQueuePriority).
///      Runs against a pinned Hoodi fork; skipped when RPC_URL is unset or points elsewhere.
///      Each case runs against both a direct and a proxied instance.
contract QueueDetectionTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    uint256 internal constant HOODI_FORK_BLOCK = 3495000;
    address internal constant STAKING_ROUTER =
        0xCc820558B39ee15C7C45B59390B503b83fb499A8;
    uint256 internal constant CSM_MODULE_ID = 4;
    uint256 internal constant CMV2_MODULE_ID = 5;
    address internal constant CMV2_ADDRESS =
        0x87EB69Ae51317405FD285efD2326a4a11f6173b9;
    address internal constant PROXY_ADMIN = address(0xA11CE);

    SMDiscovery[] internal instances;

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

        SMDiscovery implementation = new SMDiscovery(STAKING_ROUTER);
        OssifiableProxy proxy = new OssifiableProxy(
            address(implementation),
            PROXY_ADMIN,
            ""
        );

        instances.push(new SMDiscovery(STAKING_ROUTER));
        instances.push(SMDiscovery(address(proxy)));

        for (uint256 i = 0; i < instances.length; i++) {
            instances[i].updateModuleCache(CSM_MODULE_ID);
            instances[i].updateModuleCache(CMV2_MODULE_ID);
        }
    }

    function test_csmQueueBatches_returnsNonEmpty() external view {
        assertEq(instances.length, 2);
        for (uint256 i = 0; i < instances.length; i++) {
            Batch[] memory batches = instances[i].getDepositQueueBatches(
                CSM_MODULE_ID,
                5,
                0,
                10
            );
            assertGt(batches.length, 0);
        }
    }

    function test_csmQueueBatches_revertsOnPriorityAboveRegistryBound()
        external
    {
        assertEq(instances.length, 2);
        for (uint256 i = 0; i < instances.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(InvalidQueuePriority.selector, 6, 5)
            );
            instances[i].getDepositQueueBatches(CSM_MODULE_ID, 6, 0, 10);
        }
    }

    function test_cmv2QueueBatches_revertsAsUnsupported() external {
        assertEq(instances.length, 2);
        for (uint256 i = 0; i < instances.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ModuleDoesNotSupportQueueOperations.selector,
                    CMV2_ADDRESS
                )
            );
            instances[i].getDepositQueueBatches(CMV2_MODULE_ID, 0, 0, 10);
        }
    }
}
