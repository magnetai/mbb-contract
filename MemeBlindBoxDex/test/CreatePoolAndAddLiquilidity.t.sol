// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std-1.9.4/src/Test.sol";
import {MemeBlindBoxDex} from "../src/MemeBlindBoxDex.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.0/token/ERC20/IERC20.sol";
import {Util} from "./Util.sol";


interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function burn(uint256 tokenId) external payable;
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
    external
    payable
    returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function liquidity() external view returns (uint128);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        // uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}


contract CreatePoolAndAddLiquilidity is Test, Util {
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    MemeBlindBoxDex public machine;
    string public BASE_RPC = vm.envString("BASE_RPC");
    address public NONFUNGIBLE_POSITION_MANAGER = vm.envAddress("NONFUNGIBLE_POSITION_MANAGER_BASE");
    address public SWAP_ROUTER = vm.envAddress("SWAP_ROUTER_BASE");
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public executor = makeAddr("executor");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address[] public users;
    // address public positionManager = 

    function setUp() public {
        vm.createSelectFork(BASE_RPC);
        vm.startPrank(deployer);
        machine = new MemeBlindBoxDex(NONFUNGIBLE_POSITION_MANAGER);

        machine.grantRole(machine.PROCESSOR_ROLE(), address(this));
        machine.grantRole(machine.AI_PROCESSOR_ROLE(), address(this));
        machine.grantRole(machine.PROCESSOR_ROLE(), operator);
        machine.grantRole(machine.AI_PROCESSOR_ROLE(), executor);

        machine.grantRole(machine.PROCESSOR_ROLE(), deployer);
        machine.grantRole(machine.AI_PROCESSOR_ROLE(), deployer);
        vm.stopPrank();
    }

    function test_CreatePoolAndLockLiquidity() public returns(address pool, uint256 tokenId) {
        uint256 blockNumber = 100;
        uint256 userSharePercentage = 50;

        contribute(machine, user1, 10_000 ether, blockNumber);
        vm.roll(blockNumber + 1);
        address token = createToken(machine, executor, "test", "TEST", userSharePercentage, blockNumber);

        (uint256 depositRatio_, uint256 endBlock_, uint256 donateAmount_, ) = machine.tokenInfo(token);
        
        assertEq(depositRatio_, userSharePercentage);
        assertEq(endBlock_, blockNumber);
        assertEq(donateAmount_, 10_000 ether);

        uint160 sqrtPriceX96 = getSqrtPriceX96(machine);
        createPoolAndLockLiquidity(machine, executor, token, machine.WETH(), sqrtPriceX96);

        distribute(machine, executor);

        routerSwap(user1, token, machine.WETH(), machine.POOL_FEE(), 10 ether); 
        routerSwap(user1, machine.WETH(), token, machine.POOL_FEE(), 10 ether); 
    }

    function test_CollectLiquidity() public returns(address pool, uint256 tokenId) {
        uint256 blockNumber = 100;
        uint256 userSharePercentage = 50;

        contribute(machine, user1, 10_000_000 ether, blockNumber);
        vm.roll(blockNumber + 1);
        address token = createToken(machine, executor, "test", "TEST", userSharePercentage, blockNumber);
        // token < weth
        // console.log("token", token);
        emit log_named_address("token", token);
        (uint256 depositRatio_, uint256 endBlock_, uint256 donateAmount_, ) = machine.tokenInfo(token);
        
        assertEq(depositRatio_, userSharePercentage);
        assertEq(endBlock_, blockNumber);
        assertEq(donateAmount_, 10_000_000 ether);

        uint160 sqrtPriceX96 = getSqrtPriceX96(machine);
        (pool, tokenId) = createPoolAndLockLiquidity(machine, executor, token, machine.WETH(), sqrtPriceX96);
        routerSwap(user1, machine.WETH(), token, machine.POOL_FEE(), 100 ether);
        routerSwap(user1, token, machine.WETH(), machine.POOL_FEE(), 1 ether);
        
        distribute(machine, executor);

        (uint256 amount0, uint256 amount1) =  machine.collectLiquidityTax(tokenId);
        assertGt(amount0, 0, 'amount0 is 0');
        assertGt(amount1, 0, 'amount1 is 0');
        emit log_named_uint('amount0 is: ', amount0);
        emit log_named_uint('amount1 is: ', amount1);
    }

    function routerSwap(address user, address tokenIn, address tokenOut, uint24 fee, uint256 amount) public {
        // (tokenIn, tokenOut) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        emit log_string('start swap test...');

        vm.startPrank(user);
        if (tokenIn == machine.WETH()) {
            deal(machine.WETH(), user, amount);
        }
        IERC20(tokenIn).approve(SWAP_ROUTER, amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: user,
            // deadline: block.timestamp + 1000,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0    
        }); 
        uint256 amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
        vm.stopPrank();
    }

    function test_happyCase() public {
        // 1. create MeMe
        assertEq(machine.currentStartBlock(), 0);
        assertEq(machine.currentEndBlock(), 0);
        assertEq(machine.lastContributionBlock(), 0);
        // 2. contribute
        uint256 blockNumber = 100;
        uint256 userSharePercentage = 50;
        assertEq(machine.checkDistributeState(), true, "distribute state is not true");
        contribute(machine, user1, 1 ether, blockNumber);
        assertEq(machine.lastContributionBlock(), blockNumber);

        contribute(machine, user2, 1 ether, blockNumber + 1);
        contribute(machine, user3, 1 ether, blockNumber + 1);
        contribute(machine, user3, 1 ether, blockNumber + 2);
        contribute(machine, executor, 1 ether, blockNumber + 3);
        contribute(machine, executor, 1 ether, blockNumber + 3);
        // lastContributionBlock
        assertEq(machine.lastContributionBlock(), blockNumber + 3);

        // blockInfo
        uint256 usersLength = machine.getBlockUsersLength(blockNumber);
        assertEq(usersLength, 1);
        usersLength = machine.getBlockUsersLength(blockNumber + 1);
        assertEq(usersLength, 2);
        usersLength = machine.getBlockUsersLength(blockNumber + 2);
        assertEq(usersLength, 1);

        // totalDonate
        (,,uint256 contributeAmount, uint256 donateValue) = machine.contributeBlockInfo(blockNumber);
        assertEq(donateValue, 1 ether, 'donateValue is false');
        assertEq(contributeAmount, 1, 'contributeAmount is false');
        (,,contributeAmount, donateValue) = machine.contributeBlockInfo(blockNumber + 1);
        assertEq(donateValue, 3 ether, 'donateValue is false');
        assertEq(contributeAmount, 3, 'contributeAmount is false');

        // currentStartBlock, currentEndBlock
        assertEq(machine.currentStartBlock(), 0);
        assertEq(machine.currentEndBlock(), 0);

        // vm.roll(blockNumber + 2);
        // 3.createToken
        address token = createToken(machine, executor, "test", "TEST",  userSharePercentage, blockNumber + 1);
        assertEq(machine.checkDistributeState(), false, "distribute state is not false");
        assertEq(machine.currentToken(), token, "current token address is false");

        // currentStartBlock, currentEndBlock
        assertEq(machine.currentStartBlock(), blockNumber);
        assertEq(machine.currentEndBlock(), blockNumber + 1);

        // tokenInfo
        (uint256 depositRatio_, uint256 endBlock_, uint256 donateAmount_, ) = machine.tokenInfo(token);
        assertEq(depositRatio_, userSharePercentage);
        assertEq(endBlock_, blockNumber + 1);
        // assertEq(donateAmount_, 3 ether, 'contributeAmount is false');

        // 4. createPoolAndLockLiquidity
        (uint256 wethBalance, uint256 tokenBalance) = machine.getPairLiquidityAmountInContract(machine.currentToken());
        emit log_named_uint('tokenBalance', tokenBalance);
        // assertEq(wethBalance, 3 ether, 'contributeAmount is false');
        assertEq(token < machine.WETH(), true, "token is not greater than weth");

        uint160 sqrtPriceX96 = getSqrtPriceX96(machine);
        createPoolAndLockLiquidity(machine, executor, machine.currentToken(), machine.WETH(), sqrtPriceX96);

        // 5.distribute
        distribute(machine, executor);
        assertEq(machine.checkDistributeState(), true, "distribute state is not true");

        // currentStartBlock, currentEndBlock
        assertEq(machine.currentStartBlock(), blockNumber + 1);
        assertEq(machine.currentEndBlock(), blockNumber + 1);

        createTokenToLockLiquidity(machine, executor, blockNumber + 3, 50);
    }

}
