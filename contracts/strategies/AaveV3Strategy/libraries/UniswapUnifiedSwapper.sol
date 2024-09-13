// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

/**
 *   @title UniswapUnifiedSwapper
 *   @author Cavies Labs
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that would like to use Uniswap V2 or V3 for swaps. It holds all needed
 *   logic to perform exact input swaps. Using UniswapV2Swapper and UniswapV3Swapper.
 *
 */
contract UniswapUnifiedSwapper {
    using SafeERC20 for ERC20;

    // Optional Variable to be set to not sell dust.
    uint256 public minAmountToSell;

    // Base tokens for swaps. Defaults to WSEI on mainnet.
    address public base = 0xE30feDd158A2e3b13e9badaeABaFc5516e95e8C7;

    // Uni Swap router to use. Defaults to DragonSwap router on mainnet.
    address public router = 0x11DA6463D6Cb5a03411Dbf5ab6f6bc3997Ac7428;

    // Uni V3 Swap router to use. Defaults to DragonSwap router on mainnet.
    address public v3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // Fees for the Uni V3 pools. Each fee should get set each way in
    // the mapping so no matter the direction the correct fee will get
    // returned for any two tokens.
    mapping(address => mapping(address => uint24)) public uniFees;

    // Uni Router flag to use for specific tokens. Enable true for selected token if V3 is to be used.
    // Defaults to V2 for all tokens, since initialized values are false.
    mapping(address => bool) public useV3Router;

    /**
    * @dev Set router and v3Router addresses.
    * @param _v2router The router to use for V2 swaps.
    * @param _v3router The router to use for V3 swaps.
    */
    function _setRouter(
        address _v2router,
        address _v3router
    ) internal {
        router = _v2router;
        v3Router = _v3router;
    }

    /**
     * @dev Used to set a specific token to use router V3 instead of
     * default option which is v2.
     *
     * @param _token The token to configure.
     * @param _useV3 To use v2 or v3.
     */
    function _setUseV3Router(address _token, bool _useV3) internal {
        useV3Router[_token] = _useV3;
    }

    /**
     *  @dev All fess will default to 0 on creation. A strategist will need
     * To set the mapping for the tokens expected to swap. This function
     * is to help set the mapping. It can be called internally during
     * initialization, through permissioned functions etc.
     */
    function _setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) internal {
        uniFees[_token0][_token1] = _fee;
        uniFees[_token1][_token0] = _fee;
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will send the swap through the according swap method from the
     * current router version in use.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     */
    function _swapFrom(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 _amountOut) {
        if (useV3Router[_from]) {
            _amountOut = _swapFromV3(_from, _to, _amountIn, _minAmountOut);
        } else {
            _amountOut =_swapFromV2(_from, _to, _amountIn, _minAmountOut);
        }
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountOut`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * The corresponding uniFees for each token pair will need to be set
     * other wise this function will revert.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _swapFromV3(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal returns (uint256 _amountOut) {
        if (_amountIn > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);
            if (_from == base || _to == base) {
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams(
                    _from, // tokenIn
                    _to, // tokenOut
                    uniFees[_from][_to], // from-to fee
                    address(this), // recipient
                    _amountIn, // amountIn
                    _minAmountOut, // amountOut
                    0 // sqrtPriceLimitX96
                );

                _amountOut = ISwapRouter(v3Router).exactInputSingle(params);
            } else {
                bytes memory path = abi.encodePacked(
                    _from, // tokenIn
                    uniFees[_from][base], // from-base fee
                    base, // base token
                    uniFees[base][_to], // base-to fee
                    _to // tokenOut
                );

                _amountOut = ISwapRouter(v3Router).exactInput(
                    ISwapRouter.ExactInputParams(
                        path,
                        address(this),
                        _amountIn,
                        _minAmountOut
                    )
                );
            }
        }
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountToSell`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     */
    function _swapFromV2(
        address _from,
        address _to,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns(uint256 _amountOut){
        if (_amountIn > minAmountToSell) {
            _checkAllowance(router, _from, _amountIn);

            _amountOut = IUniswapV2Router02(router).swapExactTokensForTokens(
                _amountIn,
                _minAmountOut,
                _getTokenOutPath(_from, _to),
                address(this)
            );
        }
    }

    /**\
     * @dev Internal function to get a quoted amount out of token sale.
     *
     * NOTE: This can be easily manipulated and should not be relied on
     * for anything other than estimations.
     *
     * @param _from The token to sell.
     * @param _to The token to buy.
     * @param _amountIn The amount of `_from` to sell.
     * @return . The expected amount of `_to` to buy.
     */
    function _getAmountOut(
        address _from,
        address _to,
        uint256 _amountIn
    ) internal view returns (uint256) {
        uint256[] memory amounts = IUniswapV2Router02(router).getAmountsOut(
            _amountIn,
            _getTokenOutPath(_from, _to)
        );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Internal function used to easily get the path
     * to be used for any given tokens.
     *
     * @param _tokenIn The token to swap from.
     * @param _tokenOut The token to swap to.
     * @return _path Ordered array of the path to swap through.
     */
    function _getTokenOutPath(
        address _tokenIn,
        address _tokenOut
    ) internal view returns (address[] memory _path) {
        bool isBase = _tokenIn == base || _tokenOut == base;
        _path = new address[](isBase ? 2 : 3);
        _path[0] = _tokenIn;

        if (isBase) {
            _path[1] = _tokenOut;
        } else {
            _path[1] = base;
            _path[2] = _tokenOut;
        }
    }

    /**
     * @dev Internal safe function to make sure the contract you want to
     * interact with has enough allowance to pull the desired tokens.
     *
     * @param _contract The address of the contract that will move the token.
     * @param _token The ERC-20 token that will be getting spent.
     * @param _amount The amount of `_token` to be spent.
     */
    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (ERC20(_token).allowance(address(this), _contract) < _amount) {
            ERC20(_token).safeApprove(_contract, 0);
            ERC20(_token).safeApprove(_contract, _amount);
        }
    }

}