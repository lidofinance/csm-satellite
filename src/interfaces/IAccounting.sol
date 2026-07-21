// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IAccounting {
    /// @dev Bond lock structure.
    /// - amount |> amount of locked bond (raw storage value; may be non-zero even after expiry)
    /// - until  |> timestamp until which the lock is retained; if <= block.timestamp lock is expired
    struct BondLockData {
        uint128 amount;
        uint128 until;
    }

    /// @notice Get bond curve ID for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Bond curve ID
    function getBondCurveId(uint256 nodeOperatorId) external view returns (uint256);

    /// @notice Get information about the locked bond for the given Node Operator
    /// @param nodeOperatorId ID of the Node Operator
    /// @return Locked bond info {amount, until}
    function getLockedBondInfo(uint256 nodeOperatorId) external view returns (BondLockData memory);
}
