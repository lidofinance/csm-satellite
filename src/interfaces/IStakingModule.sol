// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

/// @title Base interface for Lido staking modules
/// @notice Common interface implemented by CSModule and CuratedModule v2
/// @dev Modules implementing this interface are compatible with SMDiscovery for basic discovery operations
interface IStakingModule {
    struct NodeOperator {
        uint32 totalAddedKeys;
        uint32 totalWithdrawnKeys;
        uint32 totalDepositedKeys;
        uint32 totalVettedKeys;
        uint32 stuckValidatorsCount;
        uint32 depositableValidatorsCount;
        uint32 targetLimit;
        uint8 targetLimitMode;
        uint32 totalExitedKeys;
        uint32 enqueuedCount;
        address managerAddress;
        address proposedManagerAddress;
        address rewardAddress;
        address proposedRewardAddress;
        bool extendedManagerPermissions;
        bool usedPriorityQueue;
    }

    struct NodeOperatorManagementProperties {
        address managerAddress;
        address rewardAddress;
        bool extendedManagerPermissions;
    }

    /// @notice Get node operator data by ID
    /// @param nodeOperatorId ID of the node operator
    /// @return NodeOperator struct with operator data
    function getNodeOperator(
        uint256 nodeOperatorId
    ) external view returns (NodeOperator memory);

    /// @notice Get node operator management properties
    /// @param nodeOperatorId ID of the node operator
    /// @return NodeOperatorManagementProperties struct with management data
    function getNodeOperatorManagementProperties(
        uint256 nodeOperatorId
    ) external view returns (NodeOperatorManagementProperties memory);

    /// @notice Get total count of registered node operators
    /// @return Total number of node operators
    function getNodeOperatorsCount() external view returns (uint256);

    /// @notice Get the accounting contract address
    /// @return Address of the accounting contract
    function ACCOUNTING() external view returns (address);
}
