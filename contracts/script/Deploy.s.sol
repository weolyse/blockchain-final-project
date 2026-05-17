// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ConstantProductAMM} from "../src/amm/ConstantProductAMM.sol";
import {AMMFactory} from "../src/amm/AMMFactory.sol";
import {DeFiGovernor} from "../src/governance/DeFiGovernor.sol";
import {DeFiTimelock} from "../src/governance/DeFiTimelock.sol";
import {Treasury} from "../src/governance/Treasury.sol";
import {LendingPoolV1} from "../src/lending/LendingPoolV1.sol";
import {PriceFeedAdapter} from "../src/oracles/PriceFeedAdapter.sol";
import {GovToken} from "../src/tokens/GovToken.sol";
import {LPToken} from "../src/tokens/LPToken.sol";
import {PositionNFT} from "../src/tokens/PositionNFT.sol";
import {ILendingStrategy, YieldVault} from "../src/vault/YieldVault.sol";
import {MockAggregator} from "../test/mocks/MockAggregator.sol";

contract Deploy is Script {
    uint256 private constant LOCAL_CHAIN_ID = 31_337;
    uint256 private constant ARBITRUM_SEPOLIA_CHAIN_ID = 421_614;
    int256 private constant MOCK_GOV_PRICE = 1e8;
    bytes32 private constant DEFAULT_PAIR_SALT = keccak256("DEFI_SUPER_APP_PAIR");

    struct Deployed {
        GovToken govToken;
        LPToken utilityToken;
        PositionNFT positionNFT;
        address feed;
        PriceFeedAdapter priceFeedAdapter;
        AMMFactory factory;
        address pair;
        LendingPoolV1 lendingImplementation;
        LendingPoolV1 lendingPool;
        Treasury treasury;
        YieldVault vault;
        DeFiTimelock timelock;
        DeFiGovernor governor;
    }

    function run() external {
        string memory deploymentPath = _deploymentPath();
        if (vm.exists(deploymentPath)) {
            console2.log("Deployment file already exists, skipping redeploy:", deploymentPath);
            return;
        }

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);
        bytes32 pairSalt = vm.envOr("PAIR_SALT", DEFAULT_PAIR_SALT);

        vm.startBroadcast(deployerKey);

        Deployed memory d;
        d.govToken = new GovToken(deployer);
        d.utilityToken = new LPToken(deployer, "DeFi Utility Token", "DUT");
        d.positionNFT = new PositionNFT(deployer);
        d.feed = _deployOrLoadFeed();
        d.priceFeedAdapter = new PriceFeedAdapter();
        d.factory = new AMMFactory();
        d.pair = d.factory.createPair2(address(d.govToken), address(d.utilityToken), pairSalt);
        d.lendingImplementation = new LendingPoolV1();

        ERC1967Proxy lendingProxy = new ERC1967Proxy(
            address(d.lendingImplementation),
            abi.encodeCall(LendingPoolV1.initialize, (deployer, address(d.positionNFT)))
        );
        d.lendingPool = LendingPoolV1(address(lendingProxy));
        d.positionNFT.grantRole(d.positionNFT.MINTER_ROLE(), address(d.lendingPool));
        d.lendingPool.setAssetConfig(address(d.govToken), d.feed, 7_500, true);
        d.treasury = new Treasury(deployer);
        d.vault = new YieldVault(d.govToken, ILendingStrategy(address(d.lendingPool)), address(d.treasury), deployer);
        d.timelock = new DeFiTimelock(deployer);
        d.governor = new DeFiGovernor(d.govToken, TimelockController(payable(address(d.timelock))));

        d.timelock.grantRole(d.timelock.PROPOSER_ROLE(), address(d.governor));
        d.timelock.grantRole(d.timelock.EXECUTOR_ROLE(), address(d.governor));
        d.timelock.revokeRole(d.timelock.DEFAULT_ADMIN_ROLE(), deployer);
        d.lendingPool.transferOwnership(address(d.timelock));
        d.vault.transferOwnership(address(d.timelock));
        d.treasury.transferOwnership(address(d.timelock));
        d.govToken.grantRole(d.govToken.MINTER_ROLE(), address(d.timelock));

        vm.stopBroadcast();

        _writeDeployment(deploymentPath, deployer, d);
    }

    function _deployOrLoadFeed() private returns (address feed) {
        if (block.chainid == LOCAL_CHAIN_ID || block.chainid == ARBITRUM_SEPOLIA_CHAIN_ID) {
            feed = address(new MockAggregator(8, MOCK_GOV_PRICE));
        } else {
            feed = vm.envAddress("PRICE_FEED");
        }
    }

    function _deploymentPath() private view returns (string memory) {
        return string.concat(_deploymentDirectory(), "/", vm.toString(block.chainid), ".json");
    }

    function _deploymentDirectory() private view returns (string memory) {
        string memory projectRoot = vm.projectRoot();
        string memory repoRootDeployments = string.concat(projectRoot, "/deployments");
        if (vm.exists(repoRootDeployments)) {
            return repoRootDeployments;
        }

        return string.concat(projectRoot, "/../deployments");
    }

    function _writeDeployment(string memory deploymentPath, address deployer, Deployed memory d) private {
        string memory root = "deployment";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeAddress(root, "deployer", deployer);
        vm.serializeAddress(root, "govToken", address(d.govToken));
        vm.serializeAddress(root, "utilityToken", address(d.utilityToken));
        vm.serializeAddress(root, "positionNFT", address(d.positionNFT));
        vm.serializeAddress(root, "priceFeed", d.feed);
        vm.serializeAddress(root, "priceFeedAdapter", address(d.priceFeedAdapter));
        vm.serializeAddress(root, "ammFactory", address(d.factory));
        vm.serializeAddress(root, "ammPair", d.pair);
        vm.serializeAddress(root, "lendingImplementation", address(d.lendingImplementation));
        vm.serializeAddress(root, "lendingPool", address(d.lendingPool));
        vm.serializeAddress(root, "treasury", address(d.treasury));
        vm.serializeAddress(root, "yieldVault", address(d.vault));
        vm.serializeAddress(root, "timelock", address(d.timelock));
        string memory json = vm.serializeAddress(root, "governor", address(d.governor));
        vm.writeJson(json, deploymentPath);

        ConstantProductAMM deployedPair = ConstantProductAMM(d.pair);
        console2.log("Deployment written:", deploymentPath);
        console2.log("GovToken:", address(d.govToken));
        console2.log("AMM pair:", d.pair);
        console2.log("Pair LP token:", deployedPair.lpToken());
        console2.log("Lending proxy:", address(d.lendingPool));
        console2.log("Governor:", address(d.governor));
    }
}
