// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {Batch} from "./IBatch.sol";

interface ICSModule {
    function PARAMETERS_REGISTRY() external view returns (address);

    function depositQueuePointers(
        uint256 queuePriority
    ) external view returns (uint128 head, uint128 tail);

    function depositQueueItem(
        uint256 queuePriority,
        uint128 index
    ) external view returns (Batch);
}
