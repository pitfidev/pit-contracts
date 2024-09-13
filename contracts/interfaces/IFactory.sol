
/**
 * @title YearnV3 Registry
 * @notice
 *  Serves as an on chain registry to track any Yearn
 *  vaults and strategies that a certain party wants to
 *  endorse.
 *
 *  Can also be used to deploy new vaults of any specific
 *  API version.
 */
interface IFactory {
    function apiVersion() external view returns (string memory);
}
