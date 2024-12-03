// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std-1.9.4/src/Test.sol";
import {MemeBlindBoxDex} from "../src/MemeBlindBoxDex.sol";
import {IERC20} from "@openzeppelin-contracts-5.0.0/token/ERC20/IERC20.sol";
import {Util} from "./Util.sol";


contract Mint is Test, Util {
    string public BASE_RPC = vm.envString("BASE_RPC");
    address public NONFUNGIBLE_POSITION_MANAGER = vm.envAddress("NONFUNGIBLE_POSITION_MANAGER_BASE");
    MemeBlindBoxDex public machine;
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public executor = makeAddr("executor");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address[] public users;

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
        string memory version = machine.version();
        assertEq(keccak256(bytes(version)), keccak256(bytes("v1")), 'version is false');
    }

    function test_Contribute( uint256 amount, uint256 number) public {
        uint256 blockNumber = 100;
        vm.assume(amount > 0 && amount < 100_000 ether);
        vm.assume(number > 10 && number < 1000);
        address[] memory accounts = randomCreateAccounts(number);

        for (uint256 i = 0; i < accounts.length; i++) {
            contribute(machine, accounts[i], amount, blockNumber);
        }
        contribute(machine, accounts[5], amount, blockNumber);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (i == 5) {
                assertEq(machine.getUserContributionFromBlock(blockNumber, accounts[i]), amount * 2);
            } else {
                assertEq(machine.getUserContributionFromBlock(blockNumber, accounts[i]), amount);
            }
        }

        (uint256 index,uint256 nextBlock,,) = machine.contributeBlockInfo(blockNumber);
        assertEq(index, 0, 'index value is false');
        assertEq(nextBlock, 0,'nextBlock value is false');

        contribute(machine, accounts[5], amount, blockNumber);
        vm.startPrank(operator);
        machine.setContributeAllowed(false);
        vm.stopPrank();
        bool state = machine.isContributeAllowed();
        assertEq(state, false, 'state value is false');
        vm.expectRevert();
        contribute(machine, accounts[5], amount, blockNumber);

        vm.startPrank(operator);
        machine.setContributeAllowed(true);
        vm.stopPrank();
        contribute(machine, accounts[5], amount, blockNumber);
    }

    function test_ContributeMultiBlock(uint256 blockNumber, uint256 amount, uint256 blockCount) public {
        vm.assume(amount > 0 && amount < 100_000_000 ether);
        vm.assume(blockNumber > 0 && blockNumber < 100_000_000);
        vm.assume(blockCount > 0 && blockCount < 100);

        for (uint256 i = 0; i < blockCount; i++) {
            contribute(machine, user1, amount, blockNumber + i * 2);
        }
        for (uint256 i = 0; i < blockCount; i++) {
            if (i == blockCount - 1) {
                assertEq(machine.getNextBlock(blockNumber + i * 2), 0);
            } else {
                assertEq(machine.getNextBlock(blockNumber + i * 2), blockNumber + (i + 1) * 2);
            }
        }
    }

    function test_CreateToken(uint256 userSharePercentage) public {
        uint256 blockNumber = 100;
        uint256 contributionValue = 1 ether;
        vm.assume(userSharePercentage >= 20 && userSharePercentage <= 50);
        contribute(machine, user1, contributionValue, blockNumber);

        vm.roll(blockNumber + 1);
        address token = createToken(machine, executor, "test", "TEST", userSharePercentage, blockNumber);
        emit log_named_address("token", token);
        (uint256 userSharePercentage_, uint256 endBlock_, uint256 contributeAmount_, ) = machine.tokenInfo(token);
        assertEq(userSharePercentage_, userSharePercentage);
        assertEq(endBlock_, blockNumber);
        assertEq(contributeAmount_, contributionValue);
    }

    function test_DistributeToken1() public {
        uint256 blockNumber = 10_000;
        address[] memory accounts = randomCreateAccounts(10_000);
        uint256 endblock = blockNumber + accounts.length - 1;
        for (uint256 i = 0; i < accounts.length; i++) {
            contribute(machine, accounts[i], 1 ether, blockNumber + i);
        }

        vm.roll(blockNumber + accounts.length);
        uint256 userSharePercentage = 50;

        address token = createToken(machine, executor, "test", "TEST", userSharePercentage, endblock);
        emit log_named_address("token", token);

        (uint256 depositRatio_, uint256 endBlock_, uint256 donateAmount_, ) = machine.tokenInfo(token);
        assertEq(depositRatio_, userSharePercentage);
        assertEq(endBlock_, endblock);
        assertEq(donateAmount_, 1 ether * accounts.length, 'donateAmount value is false');

        assertEq(IERC20(token).totalSupply(), 1_000_000_000 ether, 'totalSupply value is false');
        assertEq(machine.currentStartBlock(), blockNumber, 'currentStartBlock value is false');
        assertEq(machine.currentEndBlock(), endblock, 'currentEndBlock value is false');
        assertEq(machine.getContributionBlockLength(), accounts.length, 'contributionBlock length is false');
        emit log_named_uint('ContributionBlockLength is', machine.getContributionBlockLength());

        uint160 priceX96 = getSqrtPriceX96(machine);
        createPoolAndLockLiquidity(machine, executor, token, machine.WETH(), 1);

        uint256 i = 0;
        while (!machine.checkDistributeState()) {
            i++;
            distribute(machine, executor);
        }
        emit log_named_uint('loop count', i);

        assertEq(machine.checkDistributeState(), true, 'distribute state is not false');

        vm.expectRevert(bytes("The distribution period has ended"));
        distribute(machine, executor);

        emit log_named_uint('index ', machine.getContributionBlockIndex(endblock));

        assertEq(machine.currentEndBlock(), machine.currentStartBlock(), 'currentStartBlock and currentEndBlock value is false');
        assertEq(machine.currentStartBlock(), endblock, 'currentStartBlock and endblock value is false');
        assertEq(machine.getContributionBlockIndex(endblock), 1, 'contributionBlockIndex value is false');
    }

    function test_getContributionToken() public {
        uint256 blockNumber = 100;
        uint256 userSharePercentage = 50;
        users.push(user1);
        users.push(user2);
        users.push(user3);

        contribute(machine, user1, 10 ether, blockNumber);
        contribute(machine, user2, 0.5 ether, blockNumber);
        // contribute(machine, user3, 1, blockNumber);
        blockNumber++;

        contribute(machine, user1, 499_999_000 ether, blockNumber);
        contribute(machine, user2, 0.5 ether - 1, blockNumber);
        contribute(machine, user3, 1, blockNumber);
        vm.roll(blockNumber + 1);
        emit log_named_uint('contribute amount', machine.getLatestStageContributionValue());
        emit log_named_uint('contribute count', machine.getLatestStageContributionCount());

        address token = createToken(machine, executor, "test", "TEST", userSharePercentage, blockNumber);
        emit log_named_uint('currentEndBlock is', machine.currentEndBlock());

        uint160 priceX96 = getSqrtPriceX96(machine);
        createPoolAndLockLiquidity(machine, executor, token, machine.WETH(), priceX96);

        distribute(machine, executor);
        assertGt(IERC20(token).balanceOf(user3),0,"user3 balance is 0");
        emit log_named_uint("totalSupply after distribute", IERC20(token).totalSupply());
        emit log_named_uint("Balance of user1: ", IERC20(token).balanceOf(user1));
        emit log_named_uint("Balance of user2: ", IERC20(token).balanceOf(user2));
        emit log_named_uint("Balance of user3: ", IERC20(token).balanceOf(user3));
        emit log_named_uint("Balance of machine: ", IERC20(token).balanceOf(address(machine)));
    }
}
