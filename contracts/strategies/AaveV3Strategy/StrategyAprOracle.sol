// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IStrategyInterface} from "../core/interfaces/IStrategyInterface.sol";
import {IPool} from "./interfaces/IPool.sol";
import {DataTypes} from "./libraries/DataTypes.sol";
import {IProtocolDataProvider} from "./interfaces/IProtocolDataProvider.sol";
import {IReserveInterestRateStrategy} from "./interfaces/IReserveInterestRateStrategy.sol";

contract Aave3StrategyAprOracle {
    IPool public immutable lendingPool;
    IProtocolDataProvider public immutable protocolDataProvider;

    constructor(
        address _lendingPool,
        address _protocolDataProvider
    ) {
        lendingPool = IPool(_lendingPool);
        protocolDataProvider = IProtocolDataProvider(_protocolDataProvider);
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256) {
        address asset = IStrategyInterface(_strategy).asset();
        //need to calculate new supplyRate after Deposit (when deposit has not been done yet)
        DataTypes.ReserveData memory reserveData = lendingPool
            .getReserveData(asset);

        (
            uint256 unbacked,
            ,
            ,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            ,
            ,
            ,
            uint256 averageStableBorrowRate,
            ,
            ,

        ) = protocolDataProvider.getReserveData(asset);

        (, , , , uint256 reserveFactor, , , , , ) = protocolDataProvider
            .getReserveConfigurationData(asset);

        DataTypes.CalculateInterestRatesParams memory params = DataTypes
            .CalculateInterestRatesParams(
                unbacked,
                _delta > 0 ? uint256(_delta) : 0,
                _delta < 0 ? uint256(-1 * _delta) : 0,
                totalStableDebt,
                totalVariableDebt,
                averageStableBorrowRate,
                reserveFactor,
                asset,
                reserveData.aTokenAddress
            );

        (uint256 newLiquidityRate, , ) = IReserveInterestRateStrategy(
            reserveData.interestRateStrategyAddress
        ).calculateInterestRates(params);

        return newLiquidityRate / 1e9; // divided by 1e9 to go from Ray to Wad
    }
}
