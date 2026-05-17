// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DeFiGovernor} from "../src/governance/DeFiGovernor.sol";
import {DeFiTimelock} from "../src/governance/DeFiTimelock.sol";
import {LendingPoolV1} from "../src/lending/LendingPoolV1.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract Verify is Script {
    function run() external {
        string memory deploymentDirectory = _deploymentDirectory();
        string memory deploymentPath = string.concat(deploymentDirectory, "/", vm.toString(block.chainid), ".json");
        require(vm.exists(deploymentPath), "Missing deployment file");

        string memory json = vm.readFile(deploymentPath);
        address lendingPoolAddress = vm.parseJsonAddress(json, ".lendingPool");
        address vaultAddress = vm.parseJsonAddress(json, ".yieldVault");
        address treasuryAddress = vm.parseJsonAddress(json, ".treasury");
        address timelockAddress = vm.parseJsonAddress(json, ".timelock");
        address governorAddress = vm.parseJsonAddress(json, ".governor");

        LendingPoolV1 lendingPool = LendingPoolV1(lendingPoolAddress);
        DeFiTimelock timelock = DeFiTimelock(payable(timelockAddress));
        DeFiGovernor governor = DeFiGovernor(payable(governorAddress));

        require(lendingPool.owner() == timelockAddress, "Lending owner mismatch");
        require(IOwnable(vaultAddress).owner() == timelockAddress, "Vault owner mismatch");
        require(IOwnable(treasuryAddress).owner() == timelockAddress, "Treasury owner mismatch");
        require(timelock.getMinDelay() == 2 days, "Timelock delay mismatch");
        require(governor.votingDelay() == 1 days, "Voting delay mismatch");
        require(governor.votingPeriod() == 7 days, "Voting period mismatch");
        require(governor.quorumNumerator() == 4, "Quorum mismatch");

        string memory output = string.concat(
            "Post-deployment verification passed\n",
            "chainId: ",
            vm.toString(block.chainid),
            "\n",
            "lendingPool.owner: ",
            vm.toString(lendingPool.owner()),
            "\n",
            "vault.owner: ",
            vm.toString(IOwnable(vaultAddress).owner()),
            "\n",
            "treasury.owner: ",
            vm.toString(IOwnable(treasuryAddress).owner()),
            "\n",
            "timelock.minDelay: ",
            vm.toString(timelock.getMinDelay()),
            "\n",
            "governor.votingDelay: ",
            vm.toString(governor.votingDelay()),
            "\n",
            "governor.votingPeriod: ",
            vm.toString(governor.votingPeriod()),
            "\n",
            "governor.quorumNumerator: ",
            vm.toString(governor.quorumNumerator()),
            "\n"
        );

        vm.writeFile(string.concat(deploymentDirectory, "/verification-output.txt"), output);
        console2.log(output);
    }

    function _deploymentDirectory() private view returns (string memory) {
        string memory projectRoot = vm.projectRoot();
        string memory repoRootDeployments = string.concat(projectRoot, "/deployments");
        if (vm.exists(repoRootDeployments)) {
            return repoRootDeployments;
        }

        return string.concat(projectRoot, "/../deployments");
    }
}
