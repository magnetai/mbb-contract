// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test, console} from "forge-std-1.9.4/src/Test.sol";
import {MemeBlindBoxDex} from "../src/MemeBlindBoxDex.sol";
import "@openzeppelin-contracts-5.0.0/utils/math/Math.sol";

contract Util is Test{
    function createToken(MemeBlindBoxDex machine, address user, string memory name, string memory symbol, uint256 userSharePercentage, uint256 endBlock) public returns (address) {
        vm.startPrank(user);
        address token = machine.createToken(name, symbol, userSharePercentage, endBlock);
        vm.stopPrank();
        return token;
    }

    function contribute(MemeBlindBoxDex machine, address user, uint256 amount, uint256 blockNumber) public {
        vm.roll(blockNumber);
        vm.startPrank(user);
        vm.deal(user, amount);
        (bool success,) = address(machine).call{value: amount}("");
        require(success, "Donate failed");
        vm.stopPrank();
    }

    function distribute(MemeBlindBoxDex machine, address user) public {
        vm.startPrank(user);
        machine.distribute();
        vm.stopPrank();
    }

    function createPoolAndLockLiquidity(MemeBlindBoxDex machine, address user, address token0, address token1, uint160 sqrtPriceX96) public returns (address pool, uint256 tokenId) {
        vm.startPrank(user);
        (pool, tokenId) = machine.createPoolAndLockLiquidity(token0, token1, sqrtPriceX96);
        vm.stopPrank();
    }

    function createTokenToLockLiquidity(MemeBlindBoxDex machine, address user, uint256 blockNumber, uint256 userSharePercentage) public  {
        address token = createToken(machine, user, "test", "TEST", userSharePercentage, blockNumber);
        assertEq(machine.checkDistributeState(), false, "distribute state is not false");
        assertEq(machine.currentToken(), token, "current token address is false");
        uint160 sqrtPriceX96 = getSqrtPriceX96(machine);
        createPoolAndLockLiquidity(machine, user, machine.currentToken(), machine.WETH(), sqrtPriceX96);
        distribute(machine, user);
        assertEq(machine.checkDistributeState(), true, "distribute state is not true");
        assertEq(token > machine.WETH(), true, "token is not greater than weth");
    }

    function randomCreateAccounts(uint256 count) public pure returns (address[] memory) {
        address[] memory accounts = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            accounts[i] = vm.addr(uint256(keccak256(abi.encodePacked(i))));
        }
        return accounts;
    }

    function getSqrtPriceX96(MemeBlindBoxDex machine) public view returns (uint160 priceX96) {
        if (machine.WETH() > machine.currentToken()){
            priceX96 = uint160(2 ** 96) / 10 ** 5;
        } else {
            priceX96 = uint160(2 ** 96);
        }
    }
}