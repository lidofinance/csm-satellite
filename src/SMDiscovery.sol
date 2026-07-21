// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./interfaces/IStakingRouter.sol";
import "./interfaces/IStakingModule.sol";
import "./interfaces/ICSModule.sol";
import "./interfaces/IAccounting.sol";
import {Batch} from "./interfaces/IBatch.sol";

struct ModuleCacheData {
    address moduleAddress;
    address accountingAddress;
}

struct NodeOperatorShort {
    uint256 id;
    address managerAddress;
    address rewardAddress;
    bool extendedManagerPermissions;
    uint256 curveId;
}

struct NodeOperatorProposed {
    uint256 id;
    address proposedManagerAddress;
    address proposedRewardAddress;
    bool extendedManagerPermissions;
    uint256 curveId;
}

struct NodeOperatorInfo {
    uint256 id;
    address managerAddress;
    address rewardAddress;
    bool extendedManagerPermissions;
    address proposedManagerAddress;
    address proposedRewardAddress;
    uint256 curveId;
}

struct NodeOperatorLockedBond {
    uint256 id;
    uint128 amount;
    uint128 until;
}

enum SearchMode {
    CURRENT_ADDRESSES,
    PROPOSED_ADDRESSES,
    ALL_ADDRESSES
}

// Custom errors
error InvalidLimit(uint256 provided, uint256 max);
error InvalidQueuePriority(uint256 provided, uint256 max);
error CursorBehindQueueHead(uint128 cursor, uint128 head);
error AddressCannotBeZero();
error ZeroModuleId();
error ModuleCacheNotInitialized(uint256 moduleId);
error ModuleDoesNotSupportQueueOperations(address moduleAddress);
error InvalidStakingRouterAddress();
error ModuleAlreadyCached(uint256 moduleId, address moduleAddress);

/// @title SMDiscovery - Universal discovery for Lido staking modules
/// @notice Search and pagination for Node Operators across modules via StakingRouter
/// @dev Stateless with explicit cache. Call updateModuleCache(moduleId) before queries.
contract SMDiscovery {
    // Security limit constant
    uint256 private constant MAX_BATCH_SIZE = 1000;

    /// @notice Immutable reference to StakingRouter for module discovery
    IStakingRouter public immutable STAKING_ROUTER;

    /// @notice Cache mapping from moduleId to module data (address + accounting)
    /// @dev Populated via updateModuleCache(), read by view functions
    mapping(uint256 => ModuleCacheData) public moduleCache;

    /// @notice Emitted when module cache is updated
    event ModuleCacheUpdated(uint256 indexed moduleId, address moduleAddress);

    /// @notice Constructor initializes StakingRouter reference
    /// @param _stakingRouter Address of the StakingRouter contract
    constructor(address _stakingRouter) {
        if (_stakingRouter == address(0) || _stakingRouter.code.length == 0) {
            revert InvalidStakingRouterAddress();
        }
        STAKING_ROUTER = IStakingRouter(_stakingRouter);
    }

    /// @notice Update module cache from StakingRouter (permissionless)
    /// @dev Reverts if already cached or if module doesn't implement ACCOUNTING()
    /// @param _moduleId Module ID to cache (e.g., 1 for Curated, 3 for CSM)
    function updateModuleCache(uint256 _moduleId) external {
        if (_moduleId == 0) revert ZeroModuleId();

        IStakingRouter.StakingModule memory sm = STAKING_ROUTER
            .getStakingModule(_moduleId);
        address accountingAddress = IStakingModule(sm.stakingModuleAddress)
            .ACCOUNTING();
        ModuleCacheData memory currentCache = moduleCache[_moduleId];

        if (
            currentCache.moduleAddress == sm.stakingModuleAddress &&
            currentCache.accountingAddress == accountingAddress
        ) {
            revert ModuleAlreadyCached(_moduleId, sm.stakingModuleAddress);
        }

        moduleCache[_moduleId] = ModuleCacheData({
            moduleAddress: sm.stakingModuleAddress,
            accountingAddress: accountingAddress
        });
        emit ModuleCacheUpdated(_moduleId, sm.stakingModuleAddress);
    }

    /// @notice Find Node Operator IDs by address within a range
    /// @param _searchMode Which addresses to check (current/proposed/all)
    function findNodeOperatorsByAddress(
        uint256 _moduleId,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit,
        SearchMode _searchMode
    ) external view returns (uint256[] memory) {
        (address moduleAddr, ) = _getValidatedCache(_moduleId);
        return
            _findOperators(
                moduleAddr,
                _addressToSearch,
                _offset,
                _limit,
                _searchMode
            );
    }

    /// @notice Get Node Operator details by current address
    /// @dev Only searches managerAddress and rewardAddress
    function getNodeOperatorsByAddress(
        uint256 _moduleId,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit
    ) external view returns (NodeOperatorShort[] memory) {
        (address moduleAddr, address accountingAddr) = _getValidatedCache(
            _moduleId
        );
        return
            _getOperatorsByAddress(
                moduleAddr,
                accountingAddr,
                _addressToSearch,
                _offset,
                _limit
            );
    }

    /// @notice Get Node Operator details by proposed address
    /// @dev Only searches proposedManagerAddress and proposedRewardAddress
    function getNodeOperatorsByProposedAddress(
        uint256 _moduleId,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit
    ) external view returns (NodeOperatorProposed[] memory) {
        (address moduleAddr, address accountingAddr) = _getValidatedCache(
            _moduleId
        );
        return
            _getOperatorsByProposedAddress(
                moduleAddr,
                accountingAddr,
                _addressToSearch,
                _offset,
                _limit
            );
    }

    /// @notice Get all node operators with full info (current + proposed addresses)
    /// @param _moduleId Module ID to query
    /// @param _offset Starting operator index
    /// @param _limit Maximum number of operators to return
    function getAllNodeOperators(
        uint256 _moduleId,
        uint256 _offset,
        uint256 _limit
    ) external view returns (NodeOperatorInfo[] memory) {
        (address moduleAddr, address accountingAddr) = _getValidatedCache(
            _moduleId
        );
        return _getAllOperators(moduleAddr, accountingAddr, _offset, _limit);
    }

    /// @notice Get depositable validators count for a range of operators
    /// @dev CSM-specific, reverts for unsupported modules
    function getNodeOperatorsDepositableValidatorsCount(
        uint256 _moduleId,
        uint256 _offset,
        uint256 _limit
    ) external view returns (uint32[] memory) {
        (address moduleAddr, ) = _getValidatedCache(_moduleId);
        return _getDepositableValidatorsCount(moduleAddr, _offset, _limit);
    }

    /// @notice Get deposit queue batches via linked-list traversal
    /// @dev CSM-specific, reverts for unsupported modules
    /// @param _cursorIndex Start from head (0) or use next() from previous page
    function getDepositQueueBatches(
        uint256 _moduleId,
        uint256 _queuePriority,
        uint128 _cursorIndex,
        uint256 _limit
    ) external view returns (Batch[] memory) {
        (address moduleAddr, ) = _getValidatedCache(_moduleId);
        return
            _getQueueBatches(moduleAddr, _queuePriority, _cursorIndex, _limit);
    }

    /// @notice Get Node Operators with non-zero locked bond in a paginated range
    /// @dev Pagination is over operator-ID space [_offset, _offset+_limit); the returned array contains
    ///      only operators whose stored locked-bond amount is non-zero. Callers compare `until` against
    ///      `block.timestamp` to distinguish active vs. expired locks.
    function getOperatorsWithLockedBond(
        uint256 _moduleId,
        uint256 _offset,
        uint256 _limit
    ) external view returns (NodeOperatorLockedBond[] memory) {
        (address moduleAddr, address accountingAddr) = _getValidatedCache(
            _moduleId
        );
        return
            _getOperatorsWithLockedBond(
                moduleAddr,
                accountingAddr,
                _offset,
                _limit
            );
    }

    /// @notice Get Node Operators assigned to a specific bond curve in a paginated range
    /// @dev Pagination is over operator-ID space [_offset, _offset+_limit); the returned array
    ///      contains only operators whose bond curve ID equals _curveId.
    function getOperatorsByCurveId(
        uint256 _moduleId,
        uint256 _curveId,
        uint256 _offset,
        uint256 _limit
    ) external view returns (NodeOperatorShort[] memory) {
        (address moduleAddr, address accountingAddr) = _getValidatedCache(
            _moduleId
        );
        return
            _getOperatorsByCurveId(
                moduleAddr,
                accountingAddr,
                _curveId,
                _offset,
                _limit
            );
    }

    // === INTERNAL HELPERS ===

    /// @dev Validates address (non-zero) and limit (0 < limit <= MAX_BATCH_SIZE)
    function _validateSearchParams(
        address _addressToSearch,
        uint256 _limit
    ) internal pure {
        if (_addressToSearch == address(0)) revert AddressCannotBeZero();
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }
    }

    /// @dev Calculate bounds with overflow protection, returns isEmpty if offset >= total
    function _calculateBounds(
        uint256 _offset,
        uint256 _limit,
        uint256 _totalItems
    )
        internal
        pure
        returns (uint256 startIndex, uint256 endIndex, bool isEmpty)
    {
        if (_offset >= _totalItems) {
            return (0, 0, true);
        }

        startIndex = _offset;
        endIndex = _offset + _limit;
        if (endIndex > _totalItems) {
            endIndex = _totalItems;
        }
        isEmpty = false;
    }

    /// @dev Validates cache is initialized (non-zero address)
    function _requireCacheInitialized(
        ModuleCacheData memory _cache,
        uint256 _moduleId
    ) internal pure {
        if (_cache.moduleAddress == address(0)) {
            revert ModuleCacheNotInitialized(_moduleId);
        }
    }

    /// @dev Check if operator matches address based on search mode
    function _matchesAddress(
        IStakingModule.NodeOperator memory _operator,
        address _addressToSearch,
        SearchMode _searchMode
    ) internal pure returns (bool matches) {
        if (_searchMode == SearchMode.CURRENT_ADDRESSES) {
            return (_operator.managerAddress == _addressToSearch ||
                _operator.rewardAddress == _addressToSearch);
        } else if (_searchMode == SearchMode.PROPOSED_ADDRESSES) {
            return (_operator.proposedManagerAddress == _addressToSearch ||
                _operator.proposedRewardAddress == _addressToSearch);
        } else {
            // SearchMode.ALL_ADDRESSES
            return (_operator.managerAddress == _addressToSearch ||
                _operator.rewardAddress == _addressToSearch ||
                _operator.proposedManagerAddress == _addressToSearch ||
                _operator.proposedRewardAddress == _addressToSearch);
        }
    }

    /// @dev Validates cache and returns module + accounting addresses
    function _getValidatedCache(
        uint256 _moduleId
    ) internal view returns (address moduleAddress, address accountingAddress) {
        ModuleCacheData memory cache = moduleCache[_moduleId];
        _requireCacheInitialized(cache, _moduleId);
        return (cache.moduleAddress, cache.accountingAddress);
    }

    // === INTERNAL SEARCH ===

    /// @dev Internal implementation of findNodeOperatorsByAddress
    function _findOperators(
        address _module,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit,
        SearchMode _searchMode
    ) internal view returns (uint256[] memory) {
        _validateSearchParams(_addressToSearch, _limit);

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new uint256[](0);

        uint256[] memory tempResults = new uint256[](_limit);
        uint256 resultCount = 0;

        for (uint256 i = start; i < end; i++) {
            IStakingModule.NodeOperator memory operator = module
                .getNodeOperator(i);

            if (_matchesAddress(operator, _addressToSearch, _searchMode)) {
                tempResults[resultCount] = i;
                resultCount++;
            }
        }

        uint256[] memory results = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = tempResults[i];
        }

        return results;
    }

    /// @dev Internal implementation of getNodeOperatorsByAddress
    function _getOperatorsByAddress(
        address _module,
        address _accountingAddress,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (NodeOperatorShort[] memory) {
        _validateSearchParams(_addressToSearch, _limit);

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new NodeOperatorShort[](0);

        NodeOperatorShort[] memory tempResults = new NodeOperatorShort[](
            _limit
        );
        uint256 resultCount = 0;

        for (uint256 i = start; i < end; i++) {
            IStakingModule.NodeOperatorManagementProperties
                memory operator = module.getNodeOperatorManagementProperties(i);

            if (
                operator.managerAddress == _addressToSearch ||
                operator.rewardAddress == _addressToSearch
            ) {
                tempResults[resultCount] = NodeOperatorShort({
                    id: i,
                    managerAddress: operator.managerAddress,
                    rewardAddress: operator.rewardAddress,
                    extendedManagerPermissions: operator
                        .extendedManagerPermissions,
                    curveId: IAccounting(_accountingAddress).getBondCurveId(i)
                });
                resultCount++;
            }
        }

        NodeOperatorShort[] memory results = new NodeOperatorShort[](
            resultCount
        );
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = tempResults[i];
        }

        return results;
    }

    /// @dev Internal implementation of getNodeOperatorsByProposedAddress
    function _getOperatorsByProposedAddress(
        address _module,
        address _accountingAddress,
        address _addressToSearch,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (NodeOperatorProposed[] memory) {
        _validateSearchParams(_addressToSearch, _limit);

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new NodeOperatorProposed[](0);

        NodeOperatorProposed[] memory tempResults = new NodeOperatorProposed[](
            _limit
        );
        uint256 resultCount = 0;

        for (uint256 i = start; i < end; i++) {
            IStakingModule.NodeOperator memory operator = module
                .getNodeOperator(i);

            if (
                operator.proposedManagerAddress == _addressToSearch ||
                operator.proposedRewardAddress == _addressToSearch
            ) {
                tempResults[resultCount] = NodeOperatorProposed({
                    id: i,
                    proposedManagerAddress: operator.proposedManagerAddress,
                    proposedRewardAddress: operator.proposedRewardAddress,
                    extendedManagerPermissions: operator
                        .extendedManagerPermissions,
                    curveId: IAccounting(_accountingAddress).getBondCurveId(i)
                });
                resultCount++;
            }
        }

        NodeOperatorProposed[] memory results = new NodeOperatorProposed[](
            resultCount
        );
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = tempResults[i];
        }

        return results;
    }

    /// @dev Internal implementation of getAllNodeOperators
    function _getAllOperators(
        address _module,
        address _accountingAddress,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (NodeOperatorInfo[] memory) {
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new NodeOperatorInfo[](0);

        uint256 resultCount = end - start;
        NodeOperatorInfo[] memory results = new NodeOperatorInfo[](resultCount);

        IAccounting accounting = IAccounting(_accountingAddress);
        for (uint256 i = start; i < end; i++) {
            IStakingModule.NodeOperator memory operator = module
                .getNodeOperator(i);

            results[i - start] = NodeOperatorInfo({
                id: i,
                managerAddress: operator.managerAddress,
                rewardAddress: operator.rewardAddress,
                extendedManagerPermissions: operator
                    .extendedManagerPermissions,
                proposedManagerAddress: operator.proposedManagerAddress,
                proposedRewardAddress: operator.proposedRewardAddress,
                curveId: accounting.getBondCurveId(i)
            });
        }

        return results;
    }

    // === CSM QUEUE OPERATIONS ===

    /// @dev Internal implementation of getNodeOperatorsDepositableValidatorsCount
    function _getDepositableValidatorsCount(
        address _module,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (uint32[] memory) {
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new uint32[](0);

        uint256 resultCount = end - start;
        uint32[] memory results = new uint32[](resultCount);

        for (uint256 i = start; i < end; i++) {
            IStakingModule.NodeOperator memory operator = module
                .getNodeOperator(i);
            results[i - start] = operator.depositableValidatorsCount;
        }

        return results;
    }

    /// @dev Internal implementation of getDepositQueueBatches with interface detection
    function _getQueueBatches(
        address _module,
        uint256 _queuePriority,
        uint128 _cursorIndex,
        uint256 _limit
    ) internal view returns (Batch[] memory) {
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }

        try this._tryGetQueuePriority(_module) returns (uint256 maxPriority) {
            ICSModule csModule = ICSModule(_module);
            if (_queuePriority > maxPriority) {
                revert InvalidQueuePriority(_queuePriority, maxPriority);
            }

            (uint128 head, uint128 tail) = csModule.depositQueuePointers(
                _queuePriority
            );
            if (head == tail) return new Batch[](0);

            if (_cursorIndex != 0 && _cursorIndex < head) {
                revert CursorBehindQueueHead(_cursorIndex, head);
            }

            uint128 currentIndex = _cursorIndex == 0 ? head : _cursorIndex;
            if (currentIndex >= tail) return new Batch[](0);

            Batch[] memory tempBatches = new Batch[](_limit);
            uint256 count = 0;

            while (count < _limit && currentIndex < tail) {
                Batch batch = csModule.depositQueueItem(
                    _queuePriority,
                    currentIndex
                );
                tempBatches[count] = batch;
                count++;

                uint128 nextIndex = batch.next();
                if (nextIndex >= tail) break;
                currentIndex = nextIndex;
            }

            Batch[] memory batches = new Batch[](count);
            for (uint256 i = 0; i < count; i++) {
                batches[i] = tempBatches[i];
            }
            return batches;
        } catch {
            revert ModuleDoesNotSupportQueueOperations(_module);
        }
    }

    /// @dev Helper function for interface detection (must be external for try-catch)
    function _tryGetQueuePriority(
        address _module
    ) external view returns (uint256) {
        return ICSModule(_module).QUEUE_LOWEST_PRIORITY();
    }

    /// @dev Internal implementation of getOperatorsWithLockedBond
    function _getOperatorsWithLockedBond(
        address _module,
        address _accountingAddress,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (NodeOperatorLockedBond[] memory) {
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new NodeOperatorLockedBond[](0);

        IAccounting accounting = IAccounting(_accountingAddress);
        NodeOperatorLockedBond[] memory tempResults = new NodeOperatorLockedBond[](
            end - start
        );
        uint256 resultCount = 0;

        for (uint256 i = start; i < end; i++) {
            IAccounting.BondLockData memory lock = accounting.getLockedBondInfo(
                i
            );
            if (lock.amount == 0) continue;

            tempResults[resultCount] = NodeOperatorLockedBond({
                id: i,
                amount: lock.amount,
                until: lock.until
            });
            resultCount++;
        }

        NodeOperatorLockedBond[] memory results = new NodeOperatorLockedBond[](
            resultCount
        );
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = tempResults[i];
        }
        return results;
    }

    /// @dev Internal implementation of getOperatorsByCurveId
    function _getOperatorsByCurveId(
        address _module,
        address _accountingAddress,
        uint256 _curveId,
        uint256 _offset,
        uint256 _limit
    ) internal view returns (NodeOperatorShort[] memory) {
        if (_limit == 0 || _limit > MAX_BATCH_SIZE) {
            revert InvalidLimit(_limit, MAX_BATCH_SIZE);
        }

        IStakingModule module = IStakingModule(_module);
        uint256 totalOperators = module.getNodeOperatorsCount();

        (uint256 start, uint256 end, bool isEmpty) = _calculateBounds(
            _offset,
            _limit,
            totalOperators
        );
        if (isEmpty) return new NodeOperatorShort[](0);

        IAccounting accounting = IAccounting(_accountingAddress);
        NodeOperatorShort[] memory tempResults = new NodeOperatorShort[](
            end - start
        );
        uint256 resultCount = 0;

        for (uint256 i = start; i < end; i++) {
            if (accounting.getBondCurveId(i) != _curveId) continue;

            IStakingModule.NodeOperatorManagementProperties
                memory operator = module.getNodeOperatorManagementProperties(i);

            tempResults[resultCount] = NodeOperatorShort({
                id: i,
                managerAddress: operator.managerAddress,
                rewardAddress: operator.rewardAddress,
                extendedManagerPermissions: operator.extendedManagerPermissions,
                curveId: _curveId
            });
            resultCount++;
        }

        NodeOperatorShort[] memory results = new NodeOperatorShort[](
            resultCount
        );
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = tempResults[i];
        }

        return results;
    }
}
