// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Batch} from "./IBatch.sol";

interface ICSModule {
    /// @dev QUEUE_LOWEST_PRIORITY identifies the range of available priorities: [0; QUEUE_LOWEST_PRIORITY].
    function QUEUE_LOWEST_PRIORITY() external view returns (uint256);

    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail);

    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch);
}
