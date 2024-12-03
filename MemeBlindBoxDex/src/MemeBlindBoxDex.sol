// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC721} from "@openzeppelin-contracts-5.0.0/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.0.0/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin-contracts-5.0.0/access/AccessControl.sol";
import {Token20} from "./Token20.sol";
import {IMemeBlindBoxDex} from "./interfaces/IMemeBlindBoxDex.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ContributionRecord} from "./ContributionRecord.sol";

contract MemeBlindBoxDex is ContributionRecord, AccessControl, IMemeBlindBoxDex {
    INonfungiblePositionManager private positionManager;
    address public owner;
    uint256 public currentStartBlock;
    uint256 public currentEndBlock;
    address public currentToken;
    uint256 public constant SINGLE_DISTRIBUTE_COUNT = 600;
    uint256 public constant PROFIT_RATE = 1;
    uint24 public constant POOL_FEE = 10000;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    bytes32 public constant AI_PROCESSOR_ROLE = keccak256("AI_PROCESSOR_ROLE");
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");
    string public constant version = "v1";

    mapping(address token => TokenInfo info) public tokenInfo; // Information of created tokens
    mapping (address => bool) public isAirdropToken; 

    constructor(address _positionManager) {
        owner = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _setRoleAdmin(AI_PROCESSOR_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PROCESSOR_ROLE, DEFAULT_ADMIN_ROLE);

        // Set the position manager contract
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    // Create token and set currentEndBlock and currentStartBlock
    function createToken(
        string memory name, 
        string memory symbol, 
        uint256 userSharePercentage, 
        uint256 endBlock_ 
    ) public onlyRole(AI_PROCESSOR_ROLE) returns(address) {
        // Check if the input endblock is correct
        require(contributeBlockInfo[endBlock_].accumulateContributionValue > 0, "No contribute in the endBlock_");

        // Check if there are new contributions, prevent overflow
        require(lastContributionBlock > currentEndBlock, "No contribute in the last period");

        // Check if the input endBlock_ is correct
        require(endBlock_ > currentEndBlock, "The input endblock must be greater than the current endblock");

        // Check if the last mint is completed or no mint has occurred
        require(checkDistributeState(), "The previous distribute is not completed");

        require(userSharePercentage >= 20 && userSharePercentage <= 50, "The userSharePercentage must be between 20 and 50");

        Token20 token = new Token20(name, symbol);

        currentToken = address(token);
        uint256 contributionValue;
        currentEndBlock = endBlock_;
        // Set startblock and endblock
        contributionValue = contributeBlockInfo[currentEndBlock].accumulateContributionValue - contributeBlockInfo[currentStartBlock].accumulateContributionValue;
        currentStartBlock = contributeBlockInfo[currentStartBlock].nextBlock;

        tokenInfo[currentToken] = TokenInfo(userSharePercentage, endBlock_, contributionValue, false);
        isAirdropToken[currentToken] = true;

        // charge Fee
        payable(owner).transfer(contributionValue * PROFIT_RATE / 100);

        emit CreateToken(address(token), token.totalSupply(), userSharePercentage, endBlock_, contributionValue);
        return address(token);
    }

    /**
     * @dev Execute the distribution process for the current token..
     * @notice This function can only be called by the AI_PROCESSOR_ROLE.
     * @notice The distribution period must not have ended.
     */
    function distribute() public onlyRole(AI_PROCESSOR_ROLE)  {
        require(!checkDistributeState(), "The distribution period has ended");
        uint256 totalSupply = Token20(currentToken).totalSupply();

        TokenInfo memory currentTokenInfo = tokenInfo[currentToken];
        require(currentTokenInfo.createdPool, "The token has not created pool");
        uint256 contributeAmount = currentTokenInfo.contributeAmount;

        uint256 distributeAmount = totalSupply * currentTokenInfo.userSharePercentage / 100;
        uint256 currentDistributeCount = 0;

        // Ensure i != 0 to prevent currentEndBlock from being equal to lastContributionBlock.
        for (uint256 i = currentStartBlock; (i <= currentEndBlock && i != 0); i = contributeBlockInfo[i].nextBlock) {
            uint256 length = contributeBlockInfo[i].users.length;
            uint256 currentIndex = contributeBlockInfo[i].index;

            for (uint256 j = currentIndex; j < length; j++) {
                currentDistributeCount++;
                SafeERC20.safeTransfer(
                    IERC20(currentToken),
                    contributeBlockInfo[i].users[j], 
                    contributeBlockInfo[i].balanceOf[contributeBlockInfo[i].users[j]] * distributeAmount / contributeAmount
                    );
                if (j == length - 1 || currentDistributeCount == SINGLE_DISTRIBUTE_COUNT) {
                    contributeBlockInfo[i].index = j + 1;
                    break;
                }
            }
            currentStartBlock = i;

            if (currentDistributeCount == SINGLE_DISTRIBUTE_COUNT) {
                break;
            }
        }
    }

    function createPoolAndLockLiquidity(
        address token0, 
        address token1, 
        uint160 sqrtPriceX96
    ) public onlyRole(AI_PROCESSOR_ROLE)  returns(address pool, uint256 tokenId) {
        require(isAirdropToken[token0] || isAirdropToken[token1], "Token is not airdrop token");
        require((token0 == WETH || token1 == WETH) && token0 != token1, "One of the addresses must be WETH");
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        uint256 token0Balance;
        uint256 token1Balance;
        TokenInfo memory tempTokenInfo;
        uint256 totalSupply;
        if (token0 == WETH) {
            totalSupply = Token20(token1).totalSupply();
            tempTokenInfo = tokenInfo[token1];
            require(!tempTokenInfo.createdPool, 'The token has created pool');
            token0Balance = tempTokenInfo.contributeAmount - tempTokenInfo.contributeAmount * PROFIT_RATE / 100;
            token1Balance = totalSupply - tempTokenInfo.userSharePercentage * totalSupply / 100  - PROFIT_RATE * totalSupply / 100;
            IWETH(WETH).deposit{value: token0Balance}();
            tokenInfo[token1].createdPool = true;
        } else {
            totalSupply = Token20(token0).totalSupply();
            tempTokenInfo = tokenInfo[token0];
            require(!tempTokenInfo.createdPool, 'The token has created pool');
            token1Balance = tempTokenInfo.contributeAmount - tempTokenInfo.contributeAmount * PROFIT_RATE / 100;
            token0Balance = totalSupply - tempTokenInfo.userSharePercentage * totalSupply / 100  - PROFIT_RATE * totalSupply / 100;
            IWETH(WETH).deposit{value: token1Balance}();
            tokenInfo[token0].createdPool = true;
        }

        pool = positionManager.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, sqrtPriceX96);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0, 
            token1: token1, 
            fee: POOL_FEE, 
            tickLower: -887200, 
            tickUpper: 887200, 
            amount0Desired: token0Balance, 
            amount1Desired: token1Balance, 
            amount0Min: 0, 
            amount1Min: 0, 
            recipient: address(this), 
            deadline: block.timestamp
        });

        Token20(token0).approve(address(positionManager), token0Balance);
        Token20(token1).approve(address(positionManager), token1Balance);

        (tokenId, , , ) = positionManager.mint(params);

        emit CreatePoolAndLockLiquidity(pool, tokenId);
    }

    /**
     * @dev Collects liquidity tax
     * @param tokenId The NFT ID for which to collect liquidity tax
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     * @notice Only accounts with the PROCESSOR_ROLE can call this function
     */
    function collectLiquidityTax(uint256 tokenId) external onlyRole(PROCESSOR_ROLE) returns(uint256 amount0, uint256 amount1) {
        require(IERC721(address(positionManager)).ownerOf(tokenId) == address(this), "The token is not in this contract");
        (amount0, amount1) = positionManager.collect(INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: owner,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        }));
        emit CollectLiquidityTax(tokenId, amount0, amount1);
        return (amount0, amount1);
    }

    function addAirdropToken(address token) public onlyRole(PROCESSOR_ROLE) {
        require(token!= address(0), "Token address cannot be zero");
        require(!isAirdropToken[token], "The token has already been added");
        isAirdropToken[token] = true;
    }

    // Airdrop tokens to users
    function airdropToken(address token, address[] memory users, uint256[] memory amounts) public onlyRole(AI_PROCESSOR_ROLE) {
        require(amounts.length == users.length && amounts.length > 0, "Amounts and users length mismatch");
        require(isAirdropToken[token], "Token is not airdrop token");
        for (uint256 i = 0; i < users.length; i++) {
            SafeERC20.safeTransfer(IERC20(token), users[i], amounts[i]);
        }
    }

    // Get the contribution count for the latest stage.
    function getLatestStageContributionCount() public view returns (uint256) {
        return contributeBlockInfo[lastContributionBlock].accumulateContributionCount - contributeBlockInfo[currentEndBlock].accumulateContributionCount;
    }

    // Get the contribution value for the latest stage.
    function getLatestStageContributionValue() public view returns (uint256) {
        return contributeBlockInfo[lastContributionBlock].accumulateContributionValue - contributeBlockInfo[currentEndBlock].accumulateContributionValue;
    }

    // Check if minting is completed
    function checkDistributeState() public view returns (bool) {
        return currentStartBlock == currentEndBlock && contributeBlockInfo[currentEndBlock].index == contributeBlockInfo[currentEndBlock].users.length;
    }

    // Get the available balance of two tokens in this address for creating pool
    function getPairLiquidityAmountInContract(address token) external view returns (uint256 wethBalance, uint256 tokenBalance) {
        require(isAirdropToken[token], "Token is not airdrop token");
        uint256 totalSupply = Token20(token).totalSupply();
        wethBalance = tokenInfo[token].contributeAmount - tokenInfo[token].contributeAmount * PROFIT_RATE / 100;
        tokenBalance = totalSupply - tokenInfo[token].userSharePercentage * totalSupply / 100  - PROFIT_RATE * totalSupply / 100;
    }

    function setContributeAllowed(bool state) public onlyRole(PROCESSOR_ROLE) {
        _setContributeAllowed(state);
        emit SetContributeAllow(state);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
