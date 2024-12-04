// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IMemeBlindBoxDex {

    struct TokenInfo {
        uint256 userSharePercentage;
        uint256 endBlock;
        uint256 contributeAmount;
        bool createdPool;
    }

    event CreateToken(address indexed token, uint256 totalSupply, uint256 userSharePercentage, uint256 endBlock, uint256 contributeAmount);
    event CreatePoolAndLockLiquidity(address pool, uint256 tokenId);
    event CollectLiquidityTax(uint256 tokenId, uint256 amount0, uint256 amount1);
    event SetContributeAllow(bool state);

    function createToken(
        string memory name,
        string memory symbol,
        uint256 userSharePercentage,
        uint256 endBlock_
    ) external returns (address);
    function distribute() external;
    function createPoolAndLockLiquidity(address token0, address token1, uint160 sqrtPriceX96)
        external
        returns (address pool, uint256 tokenId);
    function collectLiquidityTax(uint256 tokenId) external returns(uint256 amount0, uint256 amount1);
    function airdropToken(address token, address[] memory users, uint256[] memory amounts) external;
    function getLatestStageContributionCount() external view returns (uint256 contributionCount);
    function getLatestStageContributionValue() external view returns (uint256 contributionValue);
    function onERC721Received(address operator, address, uint256 tokenId, bytes memory) external returns (bytes4);
    function checkDistributeState() external view returns (bool);
    function getPairLiquidityAmountInContract(address token) external view returns (uint256 wethBalance, uint256 currentBalance);
    function addAirdropToken(address token) external;
}