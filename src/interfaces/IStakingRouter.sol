// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.24;

/// @title Minimal IStakingRouter interface for SMDiscovery
/// @notice Contains only the subset of StakingRouter interface needed for module discovery
interface IStakingRouter {
    struct StakingModule {
        uint24 id;
        address stakingModuleAddress;
        uint16 stakingModuleFee;
        uint16 treasuryFee;
        uint16 stakeShareLimit;
        uint8 status;
        string name;
        uint64 lastDepositAt;
        uint256 lastDepositBlock;
        uint256 exitedValidatorsCount;
        uint16 priorityExitShareThreshold;
        uint64 maxDepositsPerBlock;
        uint64 minDepositBlockDistance;
    }

    /// @notice Get staking module info by module ID
    /// @param _stakingModuleId ID of the staking module
    /// @return StakingModule struct with module information
    function getStakingModule(
        uint256 _stakingModuleId
    ) external view returns (StakingModule memory);

    /// @notice Get all registered staking module IDs
    /// @return stakingModuleIds Array of module IDs
    function getStakingModuleIds()
        external
        view
        returns (uint256[] memory stakingModuleIds);
}
