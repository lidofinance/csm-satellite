// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import {IStakingRouter} from "../../src/interfaces/IStakingRouter.sol";

contract StakingRouterMock {
    mapping(uint256 => address) internal _modules;

    function setModule(uint256 id, address moduleAddress) external {
        _modules[id] = moduleAddress;
    }

    function getStakingModule(
        uint256 id
    ) external view returns (IStakingRouter.StakingModule memory sm) {
        sm.id = uint24(id);
        sm.stakingModuleAddress = _modules[id];
    }
}
