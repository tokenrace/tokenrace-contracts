// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.9;

import {ITreasury} from "./interfaces/OlympusInterfaces.sol";
import {IDistributor} from "./interfaces/OlympusInterfaces.sol";

import "./libraries/SafeERC20.sol";

import "./types/Governable.sol";
import "./types/Guardable.sol";

contract Distributor is Governable, Guardable, IDistributor {
    /* ========== DEPENDENCIES ========== */

    using SafeERC20 for IERC20;

    /* ====== VARIABLES ====== */

    IERC20 public immutable OHM;

    ITreasury public immutable treasury;

    address public immutable staking;

    mapping(uint256 => Adjust) public adjustments;

    Info[] public info;

    /* ====== CONSTRUCTOR ====== */

    constructor(
        address _treasury,
        address _ohm,
        address _staking
    ) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_ohm != address(0), "Invalid OHM address");
        require(_staking != address(0), "Invalid staking address");

        treasury = ITreasury(_treasury);
        OHM = IERC20(_ohm);
        staking = _staking;
    }

    /* ====== PUBLIC FUNCTIONS ====== */

    /**
        @notice send epoch reward to staking contract
     */
    function distribute() external {
        require(msg.sender == staking, "Only staking");

        // distribute rewards to each recipient
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].rate > 0) {
                treasury.mint(info[i].recipient, nextRewardAt(info[i].rate)); // mint and send from treasury
                adjust(i); // check for adjustment
            }
        }
    }

    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice increment reward rate for collector
     */
    function adjust(uint256 _index) internal {
        Adjust memory adjustment = adjustments[_index];

        // If adjustment needed, adjust until target is reached
        if (adjustment.rate != 0) {
            if (adjustment.add) {
                info[_index].rate += adjustment.rate;

                if (info[_index].rate >= adjustment.target) {
                    adjustments[_index].rate = 0;
                }
            } else {
                info[_index].rate -= adjustment.rate;

                if (info[_index].rate <= adjustment.target) {
                    adjustments[_index].rate = 0;
                }
            }
        }
    }

    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice view function for next reward at given rate
        @param _rate uint
        @return uint
     */
    function nextRewardAt(uint256 _rate) public view returns (uint256) {
        return OHM.totalSupply() * _rate / 1000000;
    }

    /**
        @notice view function for next reward for specified address
        @param _recipient address
        @return uint
     */
    function nextRewardFor(address _recipient) public view returns (uint256) {
        uint256 reward;
        for (uint256 i = 0; i < info.length; i++) {
            if (info[i].recipient == _recipient) {
                reward = nextRewardAt(info[i].rate);
            }
        }
        return reward;
    }

    /* ====== POLICY FUNCTIONS ====== */

    /**
        @notice adds recipient for distributions
        @param _recipient address
        @param _rewardRate uint
     */
    function addRecipient(address _recipient, uint256 _rewardRate) external onlyGovernor {
        require(_recipient != address(0));
        
        info.push(Info({
            recipient: _recipient, 
            rate: _rewardRate
        }));
    }

    /**
        @notice removes recipient for distributions
        @param _index uint
        @param _recipient address
     */
    function removeRecipient(uint256 _index, address _recipient) external {
        require(msg.sender == governor() || msg.sender == guardian(), "Caller is not governor or guardian");
        require(_recipient == info[_index].recipient);

        info[_index].recipient = address(0);
        info[_index].rate = 0;
    }

    /**
        @notice set adjustment info for a collector's reward rate
        @param _index uint
        @param _add bool
        @param _rate uint
        @param _target uint
     */
    function setAdjustment(
        uint256 _index,
        bool _add,
        uint256 _rate,
        uint256 _target
    ) external {
        require(msg.sender == governor() || msg.sender == guardian(), "Caller is not governor or guardian");

        if (msg.sender == guardian()) {
            require(_rate <= info[_index].rate * 25 / 1000, "Limiter: cannot adjust by >2.5%");
        }

        adjustments[_index] = Adjust({
            add: _add,
            rate: _rate,
            target: _target
        });
    }
}
