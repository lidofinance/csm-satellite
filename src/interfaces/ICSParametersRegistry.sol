// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

interface ICSParametersRegistry {
    /// @dev Available queue priorities are [0; QUEUE_LOWEST_PRIORITY].
    function QUEUE_LOWEST_PRIORITY() external view returns (uint256);
}
