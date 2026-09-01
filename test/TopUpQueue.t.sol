// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../src/SMDiscovery.sol";
import {MockFixture} from "./helpers/MockFixture.sol";

contract TopUpQueueTest is MockFixture {
    function test_fullQueueReturnedWithNonZeroHead() external {
        module.setTopUpQueue(true, 32, 5);
        module.pushTopUpQueueItem(0, 0);
        module.pushTopUpQueueItem(0, 1);
        module.pushTopUpQueueItem(0, 2);
        module.pushTopUpQueueItem(0, 3);
        module.pushTopUpQueueItem(0, 4);
        module.pushTopUpQueueItem(1, 0);
        module.pushTopUpQueueItem(2, 0);

        (
            bool enabled,
            uint256 limit,
            uint256 total,
            uint256 head,
            TopUpQueueEntry[] memory items
        ) = discovery.getTopUpQueueItems(MODULE_ID, 0, 10);

        assertTrue(enabled);
        assertEq(limit, 32);
        assertEq(total, 2);
        assertEq(head, 5);
        assertEq(items.length, 2);
        assertEq(items[0].nodeOperatorId, 1);
        assertEq(items[0].keyIndex, 0);
        assertEq(items[1].nodeOperatorId, 2);
        assertEq(items[1].keyIndex, 0);
    }

    function test_offsetSlicesQueueMidway() external {
        module.setTopUpQueue(true, 32, 0);
        module.pushTopUpQueueItem(1, 0);
        module.pushTopUpQueueItem(2, 0);
        module.pushTopUpQueueItem(3, 0);
        module.pushTopUpQueueItem(4, 0);

        (, , uint256 total, , TopUpQueueEntry[] memory items) = discovery
            .getTopUpQueueItems(MODULE_ID, 2, 10);

        assertEq(total, 4);
        assertEq(items.length, 2);
        assertEq(items[0].nodeOperatorId, 3);
        assertEq(items[1].nodeOperatorId, 4);
    }

    function test_offsetAtOrPastTotalReturnsEmptyItemsWithScalarsIntact()
        external
    {
        module.setTopUpQueue(true, 32, 0);
        module.pushTopUpQueueItem(1, 0);
        module.pushTopUpQueueItem(2, 0);

        (
            bool enabled,
            uint256 limit,
            uint256 total,
            uint256 head,
            TopUpQueueEntry[] memory items
        ) = discovery.getTopUpQueueItems(MODULE_ID, 2, 10);

        assertTrue(enabled);
        assertEq(limit, 32);
        assertEq(total, 2);
        assertEq(head, 0);
        assertEq(items.length, 0);
    }

    function test_revertsOnZeroLimit() external {
        module.setTopUpQueue(true, 32, 0);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 0, 1000)
        );
        discovery.getTopUpQueueItems(MODULE_ID, 0, 0);
    }

    function test_revertsOnLimitAboveMax() external {
        module.setTopUpQueue(true, 32, 0);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 1001, 1000)
        );
        discovery.getTopUpQueueItems(MODULE_ID, 0, 1001);
    }

    function test_moduleLackingTopUpQueueRevertsAsUnsupported() external {
        BareModuleMock bareModule = new BareModuleMock(address(accounting));
        router.setModule(MODULE_ID, address(bareModule));
        discovery.updateModuleCache(MODULE_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleDoesNotSupportQueueOperations.selector,
                address(bareModule)
            )
        );
        discovery.getTopUpQueueItems(MODULE_ID, 0, 10);
    }

    function test_disabledQueueStillReturnsItems() external {
        module.setTopUpQueue(false, 32, 0);
        module.pushTopUpQueueItem(1, 0);
        module.pushTopUpQueueItem(2, 0);

        (
            bool enabled,
            ,
            ,
            ,
            TopUpQueueEntry[] memory items
        ) = discovery.getTopUpQueueItems(MODULE_ID, 0, 10);

        assertFalse(enabled);
        assertEq(items.length, 2);
        assertEq(items[0].nodeOperatorId, 1);
        assertEq(items[1].nodeOperatorId, 2);
    }

    function test_revertsForUncachedModule() external {
        vm.expectRevert(
            abi.encodeWithSelector(ModuleCacheNotInitialized.selector, 99)
        );
        discovery.getTopUpQueueItems(99, 0, 10);
    }
}

/// @dev Bare module implementing only ACCOUNTING(), for interface-detection failure tests
contract BareModuleMock {
    address public accountingAddress;

    constructor(address accounting_) {
        accountingAddress = accounting_;
    }

    // solhint-disable-next-line func-name-mixedcase
    function ACCOUNTING() external view returns (address) {
        return accountingAddress;
    }
}
