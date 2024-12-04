// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std-1.9.4/src/Script.sol";
import {MemeBlindBoxDex} from "../src/MemeBlindBoxDex.sol";
import {Token20} from "../src/Token20.sol";

contract MemeBlindBoxDexScript is Script {
    address public NONFUNGIBLE_POSITION_MANAGER = vm.envAddress("NONFUNGIBLE_POSITION_MANAGER_BASE_SEPOLIA");
    MemeBlindBoxDex public machine;
    address public otherAddress = vm.envAddress("OTHER_ADDRESS");

    function run() public {
        deploy();
        // grantRole();
        // contribute();
    }

    function deploy() public {
        vm.startBroadcast(vm.envUint("DEPOLY_PRIVATE_KEY"));
        machine = new MemeBlindBoxDex(NONFUNGIBLE_POSITION_MANAGER);
        vm.stopBroadcast();
        console.log('MemeBlindBoxDex deployed at: ', address(machine));
    }

    function contribute() public {
        vm.startBroadcast(vm.envUint("OTHER_PRIVATE_KEY"));
        (bool success,) = address(machine).call{value: 0.0001 ether, gas: 200000 gwei}("");
        require(success, "Contribution failed");
        vm.stopBroadcast();
    }

    function grantRole() public {
        vm.startBroadcast(vm.envUint("DEPOLY_PRIVATE_KEY"));
        machine.grantRole(machine.PROCESSOR_ROLE(), otherAddress);
        machine.grantRole(machine.AI_PROCESSOR_ROLE(), otherAddress);
        vm.stopBroadcast();
    }
}
