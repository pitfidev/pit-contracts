// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {BaseStrategy} from "../core/BaseStrategy.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import "./interfaces/IAToken.sol";
import "./libraries/UniswapUnifiedSwapper.sol";
import "../rewards/interfaces/IRewardsEscrow.sol";

contract PitAaveV3SimpleLender is BaseStrategy, UniswapUnifiedSwapper {
    using SafeERC20 for ERC20;

    uint256 private constant INTEREST_RATE_MODE = 2;
    uint16 private constant REFERRAL_CODE = 0;
    // The pool to deposit and withdraw through.
    IPool private immutable lendingPool;

    // To get the Supply cap of an asset.
    uint256 internal constant SUPPLY_CAP_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
    uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
    uint256 internal immutable decimals;

    // The a Token specific rewards contract for claiming rewards.
    IRewardsController public immutable rewardsController;

    // Additional Rewards escrow contract
    IRewardsEscrow public additionalRewards;

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // Bool to decide to try and claim rewards. Defaults to True.
    bool public claimRewards = true;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    // to allow for reports to still work properly.
    mapping(address => uint256) public minAmountToSellMapping;

    constructor(
        address _asset,
        string memory _name,
        address _tokenized_strategy,
        address _lendingPool,
        address _weth,
        address _uniRouter,
        address _uniV3Router
    ) BaseStrategy(_asset, _name, _tokenized_strategy) {
        // Set the lending pool.
        lendingPool = IPool(_lendingPool);

        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Make sure its a real token.
        require(address(aToken) != address(0), "!aToken");

        // Set the rewards controller
        rewardsController = aToken.getIncentivesController();

        // Get aToken decimals for supply caps.
        decimals = ERC20(address(aToken)).decimals();

        // Make approve the lending pool for cheaper deposits.
        asset.safeApprove(address(lendingPool), type(uint256).max);

        // Set uni swapper values
        // We will use the minAmountToSell mapping instead.
        minAmountToSell = 0;
        base = _weth;
        router = _uniRouter;
        v3Router = _uniV3Router;
    }

    /**
     * @dev Sets the additional rewards contract.
     * Can only be called by the contract owner.
     * @param _rewardsEscrow The address of the additional rewards contract.
     */
    function setRewardsEscrow(address _rewardsEscrow) external onlyManagement {
        additionalRewards = IRewardsEscrow(_rewardsEscrow);
    }

    /**
     * @notice Set the uni fees for swaps.
     * @dev External function available to management to set
     * the fees used in the `UniswapV3Swapper.
     *
     * Any incentivized tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /**
     * @notice Set the router to use for swaps.
     * @dev External function available to management to set the
     * Uni router to use for swaps.
     *
     * @param _v2router The V2 router to use.
     * @param _v3router The V3 router to use.
     */
    function setRouter(
        address _v2router,
        address _v3router
    ) external onlyManagement {
        _setRouter(_v2router, _v3router);
    }

    /**
     * @notice Configure a token to use V3 or V2 router.
     * @dev External function available to management to set the
     * Uni router version to use for swaps for a specific token.
     * 
     * @param _token The token to configure.
     * @param _useV3 Whether to use V3 or not.
     */
    function setUseV3Router(
        address _token,
        bool _useV3
    ) external onlyManagement {
        _setUseV3Router(_token, _useV3);
    }


    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        _depositToPool(_amount);
    }

    function _depositToPool(uint256 depositAmount) internal {
        lendingPool.supply(
            address(asset),
            depositAmount,
            address(this),
            REFERRAL_CODE
        );
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        _withdrawFromPool(_amount);
    }

    function _withdrawFromPool(uint256 _amount) internal {
        lendingPool.withdraw(
            address(asset),
            Math.min(aToken.balanceOf(address(this)), _amount),
            address(this)
        );
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (claimRewards) {
            // Claim and sell any rewards to `asset`.
            _claimAndSellRewards();
        }

        _totalAssets = aToken.balanceOf(address(this)) + balanceOfAsset();
    }

    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _claimAndSellRewards() internal {
        // Claim all rewards from lending pool
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory aaveRewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);
        _sellRewardTokens(aaveRewardsList);

        // Claim additional rewards if the additionalRewards contract is set
        if (address(additionalRewards) != address(0)) {
            address[] memory additionalRewardsList = additionalRewards
                .claimAllAdditionalRewards();
            _sellRewardTokens(additionalRewardsList);
        }

        // Redeposit rewards
        uint256 currentBalance = balanceOfAsset();
        if (currentBalance > 0) _depositToPool(currentBalance);
    }

    function _sellRewardTokens(address[] memory rewardsList) private {
        // Sell any rewards that are not `asset`
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == address(asset)) {                
                continue;
            }

            uint256 balance = ERC20(token).balanceOf(address(this));
            if (balance > minAmountToSellMapping[token]) {
                _swapFrom(token, address(asset), balance, 0);
            }
        }
    }


    /**
     * @notice Gets the max amount of `asset` that an address can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The available amount the `_owner` can deposit in terms of `asset`
     *
    */
    function availableDepositLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        // Get the data configuration bitmap.
        uint256 _data = lendingPool
            .getReserveData(address(asset))
            .configuration
            .data;

        // Cannot deposit when paused or frozen.
        if (_isPaused(_data) || _isFrozen(_data)) return 0;

        uint256 supplyCap = _getSupplyCap(_data);

        // If we have no supply cap.
        if (supplyCap == 0) return type(uint256).max;

        // Supply plus any already idle funds.
        uint256 supply = aToken.totalSupply() + asset.balanceOf(address(this));

        // If we already hit the cap.
        if (supplyCap <= supply) return 0;

        // Return the remaining room.
        unchecked {
            return supplyCap - supply;
        }
    }

    /**
     * @notice Gets the supply cap of the reserve
     * @return The supply cap
     */
    function getSupplyCap() public view returns (uint256) {
        return _getSupplyCap(
            lendingPool.getReserveData(address(asset)).configuration.data
        );
    }

    /**
     * @dev Given the data configuration returns the supply cap.
     */
    function _getSupplyCap(uint256 _data) internal view returns (uint256) {
        // Get out the supply cap for the asset.
        uint256 cap = (_data & ~SUPPLY_CAP_MASK) >>
            SUPPLY_CAP_START_BIT_POSITION;
        // Adjust to the correct decimals.
        return cap * (10 ** decimals);
    }

    /**
     * @dev Paused flag is at the 60th bit
     */
    function _isPaused(uint256 _data) internal pure returns (bool) {
        // Create a mask with only the 60th bit set
        uint256 mask = 1 << 60; // Bitwise left shift by 59 positions

        // Perform bitwise AND operation to check if the 60th bit is 0.
        return (_data & mask) != 0;
    }

    /**
     * @dev Frozen flag is at the 57th bit.
     */
    function _isFrozen(uint256 _data) internal pure returns (bool) {
        // Create a mask with only the 57th bit set
        uint256 mask = 1 << 57; // Bitwise left shift by 56 positions

        // Perform bitwise AND operation to check if the 57th bit 0.
        return (_data & mask) != 0;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(address(this));;
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The available amount that can be withdrawn in terms of `asset`
     *
    */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        uint256 liquidity = asset.balanceOf(address(aToken));

        // Cannot withdraw from the pool when paused.
        if (
            _isPaused(
                lendingPool.getReserveData(address(asset)).configuration.data
            )
        ) liquidity = 0;

        return balanceOfAsset() + liquidity;
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _claimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
    }

    /**
     * @notice Set wether or not the strategy should claim and sell rewards.
     * @param _bool Wether or not rewards should be claimed and sold
     */
    function setClaimRewards(bool _bool) external onlyManagement {
        claimRewards = _bool;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }
}
