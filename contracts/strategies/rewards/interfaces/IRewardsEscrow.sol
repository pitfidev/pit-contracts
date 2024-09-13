// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IRewardsEscrow
 * @dev Interface for the RewardsEscrow contract.
 */
interface IRewardsEscrow {
    /**
     * @dev Claims all additional rewards and transfers them to the claimer.
     * Can only be executed by the authorized claimer.
     * @return The addresses of the assets transferred.
     */
    function claimAllAdditionalRewards() external returns (address[] memory);

    /**
     * @dev Sets a new claimer address.
     * Can only be called by the contract owner.
     * @param _claimer The new claimer address.
     */
    function setClaimer(address _claimer) external;

    /**
     * @dev Adds a new asset to the storage array.
     * Can only be called by the contract owner.
     * @param _asset The address of the asset to add.
     */
    function addAsset(address _asset) external;

    /**
     * @dev Removes an asset from the storage array.
     * Can only be called by the contract owner.
     * @param _asset The address of the asset to remove.
     */
    function removeAsset(address _asset) external;

    /**
     * @dev Retrieves the list of stored assets.
     * @return An array of asset addresses.
     */
    function getAssets() external view returns (address[] memory);

    /**
     * @dev Rescues ERC20 tokens sent to the contract.
     * Can only be called by the contract owner.
     * @param tokenAddress The address of the ERC20 token to rescue.
     * @param amount The amount of tokens to rescue.
     */
    function rescueERC20Tokens(address tokenAddress, uint256 amount) external;
}