// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std-1.9.4/src/Script.sol";
import {MemeBlindBoxDex} from "../src/MemeBlindBoxDex.sol";
import {Token20} from "../src/Token20.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
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
    function exactInputSingle(ExactInputSingleParams memory params) external payable returns (uint256 amountOut);
}

contract SwapRouteScript is Script {
    address public NONFUNGIBLE_POSITION_MANAGER = vm.envAddress("NONFUNGIBLE_POSITION_MANAGER_BASE_SEPOLIA");
    MemeBlindBoxDex public machine;
    address public otherAddress = vm.envAddress("OTHER_ADDRESS");
    address public SWAP_ROUTER = vm.envAddress("SWAP_ROUTER_BASE_SEPOLIA");
    address CA = vm.envAddress("CA");
    address token = vm.envAddress("TOKEN");

    function run() public {
        machine = MemeBlindBoxDex(payable(CA));

        uint256 swapValue = 0.00001 ether;
        deposit("OTHER_PRIVATE_KEY",  swapValue);

        routerSwap("OTHER_PRIVATE_KEY", machine.WETH(), token, swapValue);
        routerSwap("OTHER_PRIVATE_KEY", token, machine.WETH(), swapValue);
    }

    function deposit(string memory userPrivateKey, uint256 amount) public {
        vm.startBroadcast(vm.envUint(userPrivateKey));
        IERC20(machine.WETH()).deposit{value: amount}();
        vm.stopBroadcast();
    }

    function routerSwap(string memory userPrivateKey, address tokenIn, address tokenOut, uint256 amount) public {
        vm.startBroadcast(vm.envUint(userPrivateKey));
        IERC20(tokenIn).approve(SWAP_ROUTER, amount);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: machine.POOL_FEE(),
            recipient: msg.sender,
            // deadline: block.timestamp + 1000,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0    
        });
        uint256 amountOut = ISwapRouter(SWAP_ROUTER).exactInputSingle(params);
        console.log('amountOut is : ', amountOut);
        vm.stopBroadcast();
    }

}
