# CSModule Deposit Queue Structure and Organization

## Overview

The CSModule (Community Staking Module) implements a sophisticated multi-priority deposit queue system for managing validator keys from Node Operators. This document details the queue structure, organization, and efficient methods for aggregating keys count across all queues.

## Queue Architecture

### Multi-Priority System

The CSModule supports multiple parallel queues with different priority levels:

- **Priority Range**: `0` to `QUEUE_LOWEST_PRIORITY` (inclusive)
- **Priority 0**: Highest priority queue
- **Priority QUEUE_LOWEST_PRIORITY**: Lowest priority queue (default/fallback)
- **Legacy Priority**: `QUEUE_LEGACY_PRIORITY = QUEUE_LOWEST_PRIORITY - 1` (reserved for CSM v1 compatibility)

### Data Structure

```solidity
// Internal queue storage
mapping(uint256 queuePriority => QueueLib.Queue queue) internal _queueByPriority;
QueueLib.Queue internal _legacyQueue; // Legacy queue for backwards compatibility
```

### Queue Implementation

Each queue is implemented as a linked-list structure:

```solidity
struct Queue {
    uint128 head;    // Pointer to next item to be dequeued
    uint128 tail;    // Total number of batches ever enqueued
    mapping(uint128 => Batch) queue; // Index to Batch mapping
}
```

### Queue Index Structure

- **Sequential Indices**: Queue indices are sequential (head, head+1, head+2, etc.)
- **Direct Access**: `depositQueueItem(priority, index)` accepts any valid index between [0..tail]
- **Dual Access Patterns**: Batches can be accessed either by:
  - **Sequential index**: Direct access using `head + offset`
  - **Linked-list traversal**: Following `next()` pointers for processing order

### Batch Skipping Mechanism

Batches can be skipped during queue processing by advancing the `head` pointer:

- **Head Advancement**: The `head` pointer can only be increased (never decreased)
- **Batch Skipping**: When `head` is advanced past batch indices, those batches are effectively skipped
- **Dequeue Logic**: Only batches from current `head` to `tail` are considered for processing
- **Permanent Skip**: Once skipped (head advanced beyond), batches cannot be re-accessed in normal queue traversal

## Batch Structure

### Batch Type Definition

Each queue item is a `Batch` (packed uint256) containing:

```solidity
type Batch is uint256;

// Batch bit layout:
// [255:192] uint64  nodeOperatorId - Node Operator ID
// [191:128] uint64  keysCount      - Number of keys in this batch
// [127:0]   uint128 next           - Index of next batch in queue
```

### Batch Utility Functions

```solidity
function noId(Batch self) pure returns (uint64);    // Extract nodeOperatorId
function keys(Batch self) pure returns (uint64);    // Extract keysCount
function next(Batch self) pure returns (uint128);   // Extract next pointer
```

## Current Interface Methods

### Queue Access Methods

```solidity
// Get queue head/tail pointers for specific priority
function depositQueuePointers(uint256 queuePriority)
    external view returns (uint128 head, uint128 tail);

// Get specific batch from queue
function depositQueueItem(uint256 queuePriority, uint128 index)
    external view returns (Batch);

// Get lowest priority level -- lives on CSParametersRegistry, NOT on the module
function PARAMETERS_REGISTRY() external view returns (address);      // on CSModule
function QUEUE_LOWEST_PRIORITY() external view returns (uint256);    // on CSParametersRegistry
```

### Aggregation Methods

```solidity
// Global summary (includes depositableValidatorsCount)
function getStakingModuleSummary() external view returns (...);

// Clean empty batches across all priorities
function cleanDepositQueue() external;
```

## Keys Count Aggregation Requirements

### Current Limitations

The CSModule currently lacks efficient methods to:

1. Get total keys count across all queues/priorities
2. Get per-priority queue statistics
3. Aggregate depositable keys by priority level
4. Efficiently traverse all batches without knowing exact indices

### Aggregation Strategy Requirements

To efficiently aggregate keys count across all queues:

#### 1. Multi-Priority Iteration
- Iterate through all priority levels from `0` to `QUEUE_LOWEST_PRIORITY`
- Use `depositQueuePointers()` to get head/tail bounds for each priority

#### 2. Linked-List Traversal per Priority
- Start from `head` index for each priority queue
- Follow `next` pointers in batches until reaching `tail`
- Sum `keysCount` from each batch using `keys()` utility function

#### 3. Batch Processing Algorithm
- For each priority level:
  1. Get queue bounds: `(head, tail) = depositQueuePointers(priority)`
  2. Initialize current index: `currentIndex = head`
  3. While `currentIndex != tail`:
     - Get batch: `batch = depositQueueItem(priority, currentIndex)`
     - Add to count: `totalKeys += batch.keys()`
     - Move to next: `currentIndex = batch.next()`

## Performance Considerations

### Gas Efficiency
- **Sequential Processing**: Each queue must be traversed linearly (O(n) per queue)
- **Linked-List Traversal**: Following `next` pointers is the only way to traverse
- **Pagination Required**: Large queues may require pagination for gas efficiency
- **Empty Queue Handling**: Skip queues where `head == tail`

### Memory Optimization
- **Batch Packing**: Efficient uint256 packing reduces storage costs
- **Minimal State**: Only store essential queue state (head/tail pointers)
- **Direct Access**: Use `depositQueueItem()` for direct batch access by index
