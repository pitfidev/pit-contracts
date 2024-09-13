// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from '../strategies/AaveV3Strategy/interfaces/IWETH.sol';
import {IVault} from '../interfaces/IVault.sol';

contract WrappedTokenGateway is Ownable {

  using SafeERC20 for IERC20;

  IWETH internal immutable WETH;
  IVault internal immutable VAULT;

  /**
   * @dev Sets the WETH address and the Vault address. Infinite approves vault and sets owner.
   * @param weth Address of the Wrapped Ether contract
   * @param _owner Address of the vault contract
   **/
  constructor(address weth, IVault vault, address _owner) {
    WETH = IWETH(weth);
    VAULT = vault;
    IWETH(weth).approve(address(vault), type(uint256).max);
    transferOwnership(_owner);
  }

  /**
   * @dev deposits WETH into the vault using native ETH. A corresponding amount shares is minted.
   * @param onBehalfOf address of the user who will receive the aTokens representing the deposit
   **/
  function depositETH(address onBehalfOf) external payable {
    WETH.deposit{value: msg.value}();
    VAULT.deposit(msg.value, onBehalfOf);
  }

  /**
   * @dev withdraws the WETH shares from Vault.
   * @param amount amount of aWETH to withdraw and receive native ETH
   * @param receiver address of the user who will receive native ETH
   * @param _owner address of the shares owner
   * @param maxLoss maximum loss to take on withdrawal
   * @param strategies optional strategies to withdraw from
   */
  function withdrawETH(uint256 amount, address receiver, address _owner, uint256 maxLoss, address[] calldata strategies) external {
    VAULT.withdraw(amount, receiver, _owner, maxLoss, strategies);
    _safeTransferETH(receiver, amount);
  }

  /**
   * @dev transfer ETH to an address, revert if it fails.
   * @param to recipient of the transfer
   * @param value the amount to send
   */
  function _safeTransferETH(address to, uint256 value) internal {
    (bool success, ) = to.call{value: value}(new bytes(0));
    require(success, 'ETH_TRANSFER_FAILED');
  }

  /**
   * @dev transfer ERC20 from the utility contract, for ERC20 recovery in case of stuck tokens due
   * direct transfers to the contract address.
   * @param token token to transfer
   * @param to recipient of the transfer
   * @param amount amount to send
   */
  function emergencyTokenTransfer(address token, address to, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(to, amount);
  }

  /**
   * @dev transfer native Ether from the utility contract, for native Ether recovery in case of stuck Ether
   * due to selfdestructs or ether transfers to the pre-computed contract address before deployment.
   * @param to recipient of the transfer
   * @param amount amount to send
   */
  function emergencyEtherTransfer(address to, uint256 amount) external onlyOwner {
    _safeTransferETH(to, amount);
  }

  /**
   * @dev Get WETH address used by WrappedTokenGatewayV3
   */
  function getWETHAddress() external view returns (address) {
    return address(WETH);
  }

  /**
   * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
   */
  receive() external payable {
    require(msg.sender == address(WETH), 'Receive not allowed');
  }

  /**
   * @dev Revert fallback calls
   */
  fallback() external payable {
    revert('Fallback not allowed');
  }
}