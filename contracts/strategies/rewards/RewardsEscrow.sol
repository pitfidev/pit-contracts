// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governance} from "../core/utils/Governance.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardsEscrow
 * @dev This contract holds rewards and allows an authorized claimer to withdraw them.
 */
contract RewardsEscrow is Governance, Pausable {
    using SafeERC20 for IERC20;
    
    // Address authorized to claim rewards.
    address private claimer; 
    // The ERC20 tokens representing the rewards.
    address[] private assets; 

    /**
     * @dev Constructor to set the claimer.
     * @param _claimer The address authorized to claim rewards.
     */
    constructor(address _claimer, address _governance) Governance(_governance) {
        claimer = _claimer;
    }

    /**
     * @dev Rejects all Ether transfers to the contract.
     */
    receive() external payable {
        revert("Ether not accepted");
    }

    /**
     * @dev Fallback function to reject any invalid function calls.
     */
    fallback() external {
        revert("Invalid function call");
    }

    /**
     * @dev Claims all additional rewards and transfers them to the claimer.
     * Can only be executed by the authorized claimer.
     * @return claimedAmount The amount of asset transferred.
     */
    function claimAllAdditionalRewards() external returns (address[] memory) {
        require(msg.sender == claimer, "Not authorized");
        if (paused()) return(new address[](0));

        uint256 rewardsCount;
        address[] memory rewards = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = IERC20(assets[i]);
            uint256 balance = asset.balanceOf(address(this));
            if (balance > 0) {
                rewards[rewardsCount] = assets[i];
                rewardsCount++;
                // Transfer the balance to the claimer
                asset.safeTransfer(claimer, balance);
            }
        }

        address[] memory finalRewards = new address[](rewardsCount);
        for (uint256 i = 0; i < rewardsCount; i++) {
            finalRewards[i] = rewards[i];
        }

        return finalRewards;
    }

    /**
     * @dev Sets a new claimer address.
     * Can only be called by the contract owner.
     * @param _claimer The new claimer address.
     */
    function setClaimer(address _claimer) external onlyGovernance {
        claimer = _claimer;
    }

    /**
     * @dev Adds a new asset to the storage array.
     * Can only be called by the contract owner.
     * @param _asset The address of the asset to add.
     */
    function addAsset(address _asset) external onlyGovernance {
        assets.push(_asset);
    }

    /**
     * @dev Removes an asset from the storage array.
     * Can only be called by the contract owner.
     * @param _asset The address of the asset to remove.
     */
    function removeAsset(address _asset) external onlyGovernance {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == _asset) {
                // Move the last element into the place to delete
                assets[i] = assets[assets.length - 1];
                // Remove the last element
                assets.pop();
                break;
            }
        }
    }

    /**
     * @dev Retrieves the list of stored assets.
     * @return An array of asset addresses.
     */
    function getAssets() external view returns (address[] memory) {
        return assets;
    }

    /**
     * @dev Rescues ERC20 tokens sent to the contract.
     * Can only be called by the contract owner.
     * @param tokenAddress The address of the ERC20 token to rescue.
     * @param amount The amount of tokens to rescue.
     */
    function rescueERC20Tokens(address tokenAddress, uint256 amount) external onlyGovernance {
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }
}