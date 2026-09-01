// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import "../src/SMDiscovery.sol";
import {StakingRouterMock} from "./mocks/StakingRouterMock.sol";
import {StakingModuleMock} from "./mocks/StakingModuleMock.sol";
import {AccountingMock} from "./mocks/AccountingMock.sol";

contract ClaimerSearchTest is Test {
    uint256 internal constant MODULE_ID = 3;
    address internal constant CLAIMER = address(0xC1A1);
    address internal constant OTHER_CLAIMER = address(0xC1A2);

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

    function _addOperators(uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            module.addOperator(
                // forge-lint: disable-next-line(unsafe-typecast)
                address(uint160(0x1000 + i)),
                // forge-lint: disable-next-line(unsafe-typecast)
                address(uint160(0x2000 + i)),
                false
            );
        }
    }

    function test_findNodeOperatorsByAddress_claimerMode_returnsOnlyMatchingIds()
        external
    {
        _addOperators(4);
        accounting.setCustomRewardsClaimer(1, CLAIMER);
        accounting.setCustomRewardsClaimer(2, OTHER_CLAIMER);
        accounting.setCustomRewardsClaimer(3, CLAIMER);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.CLAIMER
        );

        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 3);
    }

    function test_currentAddressesMode_doesNotMatchClaimerOnlyAddress()
        external
    {
        _addOperators(2);
        accounting.setCustomRewardsClaimer(0, CLAIMER);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.CURRENT_ADDRESSES
        );
        assertEq(ids.length, 0);
    }

    function test_allAddressesMode_doesNotMatchClaimerOnlyAddress() external {
        _addOperators(2);
        accounting.setCustomRewardsClaimer(0, CLAIMER);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.ALL_ADDRESSES
        );
        assertEq(ids.length, 0);
    }

    function test_anyRoleMode_matchesViaManagerOnly() external {
        uint256 opId = module.addOperator(CLAIMER, address(0xBBB1), false);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.ANY_ROLE
        );
        assertEq(ids.length, 1);
        assertEq(ids[0], opId);
    }

    function test_anyRoleMode_matchesViaRewardOnly() external {
        uint256 opId = module.addOperator(address(0xAAA1), CLAIMER, false);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.ANY_ROLE
        );
        assertEq(ids.length, 1);
        assertEq(ids[0], opId);
    }

    function test_anyRoleMode_matchesViaProposedOnly() external {
        uint256 opId = module.addOperator(
            address(0xAAA1),
            address(0xBBB1),
            false
        );
        module.setProposedAddresses(opId, CLAIMER, address(0));

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.ANY_ROLE
        );
        assertEq(ids.length, 1);
        assertEq(ids[0], opId);
    }

    function test_anyRoleMode_matchesViaClaimerOnly() external {
        uint256 opId = module.addOperator(
            address(0xAAA1),
            address(0xBBB1),
            false
        );
        accounting.setCustomRewardsClaimer(opId, CLAIMER);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.ANY_ROLE
        );
        assertEq(ids.length, 1);
        assertEq(ids[0], opId);
    }

    function test_claimerMode_doesNotMatchManagerOnlyAddress() external {
        module.addOperator(CLAIMER, address(0xBBB1), false);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.CLAIMER
        );
        assertEq(ids.length, 0);
    }

    function test_claimerMode_doesNotMatchRewardOnlyAddress() external {
        module.addOperator(address(0xAAA1), CLAIMER, false);

        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            10,
            SearchMode.CLAIMER
        );
        assertEq(ids.length, 0);
    }

    function test_getNodeOperatorsByAddress_matchesClaimerAndPopulatesFields()
        external
    {
        address managerAddress = address(0xAAA1);
        address rewardAddress = address(0xBBB1);
        uint256 opId = module.addOperator(
            managerAddress,
            rewardAddress,
            true
        );
        accounting.setCustomRewardsClaimer(opId, CLAIMER);
        accounting.setBondCurveId(opId, 7);

        NodeOperatorShort[] memory results = discovery
            .getNodeOperatorsByAddress(MODULE_ID, CLAIMER, 0, 10);

        assertEq(results.length, 1);
        assertEq(results[0].id, opId);
        assertEq(results[0].managerAddress, managerAddress);
        assertEq(results[0].rewardAddress, rewardAddress);
        assertTrue(results[0].extendedManagerPermissions);
        assertEq(results[0].claimerAddress, CLAIMER);
        assertEq(results[0].curveId, 7);
    }

    function test_getNodeOperatorsByAddress_matchesManagerAsBefore()
        external
    {
        _addOperators(2);
        address managerAddress = address(0xAAA2);
        uint256 opId = module.addOperator(
            managerAddress,
            address(0xBBB2),
            false
        );
        accounting.setBondCurveId(opId, 3);

        NodeOperatorShort[] memory results = discovery
            .getNodeOperatorsByAddress(MODULE_ID, managerAddress, 0, 10);

        assertEq(results.length, 1);
        assertEq(results[0].id, opId);
        assertEq(results[0].curveId, 3);
    }

    function test_getNodeOperatorsByAddress_matchesRewardAsBefore() external {
        _addOperators(2);
        address rewardAddress = address(0xBBB3);
        uint256 opId = module.addOperator(
            address(0xAAA3),
            rewardAddress,
            false
        );
        accounting.setBondCurveId(opId, 4);

        NodeOperatorShort[] memory results = discovery
            .getNodeOperatorsByAddress(MODULE_ID, rewardAddress, 0, 10);

        assertEq(results.length, 1);
        assertEq(results[0].id, opId);
        assertEq(results[0].curveId, 4);
    }

    function test_getNodeOperatorsByAddress_returnsZeroClaimerWhenUnset()
        external
    {
        address managerAddress = address(0xAAA4);
        uint256 opId = module.addOperator(
            managerAddress,
            address(0xBBB4),
            false
        );

        NodeOperatorShort[] memory results = discovery
            .getNodeOperatorsByAddress(MODULE_ID, managerAddress, 0, 10);

        assertEq(results.length, 1);
        assertEq(results[0].id, opId);
        assertEq(results[0].claimerAddress, address(0));
    }

    function test_getAllNodeOperators_populatesClaimerAddress() external {
        uint256 op0 = module.addOperator(
            address(0xAAA5),
            address(0xBBB5),
            false
        );
        uint256 op1 = module.addOperator(
            address(0xAAA6),
            address(0xBBB6),
            false
        );
        accounting.setCustomRewardsClaimer(op1, CLAIMER);

        NodeOperatorInfo[] memory results = discovery.getAllNodeOperators(
            MODULE_ID,
            0,
            10
        );

        assertEq(results.length, 2);
        assertEq(results[op0].claimerAddress, address(0));
        assertEq(results[op1].claimerAddress, CLAIMER);
    }

    function test_getOperatorsByCurveId_populatesClaimerAddress() external {
        uint256 opId = module.addOperator(
            address(0xAAA7),
            address(0xBBB7),
            false
        );
        accounting.setBondCurveId(opId, 9);
        accounting.setCustomRewardsClaimer(opId, CLAIMER);

        NodeOperatorShort[] memory results = discovery.getOperatorsByCurveId(
            MODULE_ID,
            9,
            0,
            10
        );

        assertEq(results.length, 1);
        assertEq(results[0].id, opId);
        assertEq(results[0].claimerAddress, CLAIMER);
    }

    function test_findNodeOperatorsByAddress_revertsForZeroAddress()
        external
    {
        _addOperators(1);
        vm.expectRevert(AddressCannotBeZero.selector);
        discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            address(0),
            0,
            10,
            SearchMode.CLAIMER
        );
    }

    function test_getNodeOperatorsByAddress_revertsForZeroAddress() external {
        _addOperators(1);
        vm.expectRevert(AddressCannotBeZero.selector);
        discovery.getNodeOperatorsByAddress(MODULE_ID, address(0), 0, 10);
    }

    function test_findNodeOperatorsByAddress_revertsOnZeroLimit() external {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 0, 1000)
        );
        discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            0,
            SearchMode.CLAIMER
        );
    }

    function test_findNodeOperatorsByAddress_revertsOnLimitAboveMax()
        external
    {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 1001, 1000)
        );
        discovery.findNodeOperatorsByAddress(
            MODULE_ID,
            CLAIMER,
            0,
            1001,
            SearchMode.CLAIMER
        );
    }

    function test_getNodeOperatorsByAddress_revertsOnZeroLimit() external {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 0, 1000)
        );
        discovery.getNodeOperatorsByAddress(MODULE_ID, CLAIMER, 0, 0);
    }

    function test_getNodeOperatorsByAddress_revertsOnLimitAboveMax()
        external
    {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLimit.selector, 1001, 1000)
        );
        discovery.getNodeOperatorsByAddress(MODULE_ID, CLAIMER, 0, 1001);
    }

    function test_findNodeOperatorsByAddress_revertsForUncachedModule()
        external
    {
        vm.expectRevert(
            abi.encodeWithSelector(ModuleCacheNotInitialized.selector, 99)
        );
        discovery.findNodeOperatorsByAddress(
            99,
            CLAIMER,
            0,
            10,
            SearchMode.CLAIMER
        );
    }

    function test_getNodeOperatorsByAddress_revertsForUncachedModule()
        external
    {
        vm.expectRevert(
            abi.encodeWithSelector(ModuleCacheNotInitialized.selector, 99)
        );
        discovery.getNodeOperatorsByAddress(99, CLAIMER, 0, 10);
    }
}

/// @dev Regression test for the live claimer path against a pinned Hoodi CSM v2 fork.
///      Skipped when RPC_URL is unset or points elsewhere, matching QueueDetectionTest.
contract ClaimerSearchForkTest is Test {
    uint256 internal constant HOODI_CHAIN_ID = 560048;
    uint256 internal constant HOODI_FORK_BLOCK = 3505000;
    address internal constant STAKING_ROUTER =
        0xCc820558B39ee15C7C45B59390B503b83fb499A8;
    uint256 internal constant CSM_V2_MODULE_ID = 6;

    SMDiscovery internal discovery;

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

        discovery = new SMDiscovery(STAKING_ROUTER);
        discovery.updateModuleCache(CSM_V2_MODULE_ID);
    }

    /// @dev Proves the live Accounting answers getCustomRewardsClaimer through SMDiscovery.
    ///      The searched address is arbitrary (only zero is rejected) and the fork block is
    ///      pinned, so no operator matches it.
    function test_findNodeOperatorsByAddress_claimerMode_succeedsAgainstLiveAccounting()
        external
        view
    {
        uint256[] memory ids = discovery.findNodeOperatorsByAddress(
            CSM_V2_MODULE_ID,
            address(0xC1A1),
            0,
            100,
            SearchMode.CLAIMER
        );
        assertEq(ids.length, 0);
    }
}
