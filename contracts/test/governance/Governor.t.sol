// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Test} from "forge-std/Test.sol";
import {DeFiGovernor} from "../../src/governance/DeFiGovernor.sol";
import {DeFiTimelock} from "../../src/governance/DeFiTimelock.sol";
import {ProtocolSettings} from "../../src/governance/ProtocolSettings.sol";
import {Treasury} from "../../src/governance/Treasury.sol";
import {GovToken} from "../../src/tokens/GovToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract GovernorTest is Test {
    GovToken private token;
    DeFiTimelock private timelock;
    DeFiGovernor private governor;
    ProtocolSettings private settings;
    Treasury private treasury;
    MockERC20 private asset;

    address private voter = address(0xA11CE);
    address private voterTwo = address(0xB0B);
    address private lowPowerVoter = address(0xCAFE);
    address private smallProposer = address(0x5151);
    address private recipient = address(0xD00D);

    function setUp() public {
        token = new GovToken(address(this));
        timelock = new DeFiTimelock(address(this));
        governor = new DeFiGovernor(token, timelock);
        settings = new ProtocolSettings(address(timelock), 1);
        treasury = new Treasury(address(timelock));
        asset = new MockERC20("Treasury Asset", "TST");

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        token.mint(voter, 5_000_000e18);
        token.mint(voterTwo, 1_000_000e18);
        token.mint(lowPowerVoter, 0.5e18);

        vm.prank(voter);
        token.delegate(voter);
        vm.prank(voterTwo);
        token.delegate(voterTwo);
        vm.prank(lowPowerVoter);
        token.delegate(lowPowerVoter);

        asset.mint(address(treasury), 100e18);
        vm.roll(block.number + 1);
    }

    function testGovernanceLifecycle_FullE2E() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _parameterProposal(42);

        uint256 proposalId = _proposeFrom(voter, targets, values, calldatas, description);

        _advanceBlocks(governor.votingDelay() + 1);
        vm.prank(voter);
        governor.castVote(proposalId, 1);

        _advanceBlocks(governor.votingPeriod() + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(settings.parameter(), 42);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function testProposalThreshold_Reverts() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _parameterProposal(7);

        vm.prank(lowPowerVoter);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, description);
    }

    function testQuorum_Defeated() public {
        token.mint(smallProposer, 2e18);
        vm.prank(smallProposer);
        token.delegate(smallProposer);
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _parameterProposal(8);
        uint256 proposalId = _proposeFrom(smallProposer, targets, values, calldatas, description);

        _advanceBlocks(governor.votingDelay() + 1);
        vm.prank(smallProposer);
        governor.castVote(proposalId, 1);

        _advanceBlocks(governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function testTimelockDelay_Enforced() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _parameterProposal(9);
        uint256 proposalId = _proposeFrom(voter, targets, values, calldatas, description);

        _advanceBlocks(governor.votingDelay() + 1);
        vm.prank(voter);
        governor.castVote(proposalId, 1);

        _advanceBlocks(governor.votingPeriod() + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function testTreasuryReleaseThroughGovernance() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Release treasury funds";

        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(Treasury.release, (address(asset), recipient, 10e18));

        _passAndExecute(voter, targets, values, calldatas, description);

        assertEq(asset.balanceOf(recipient), 10e18);
    }

    function testGovernorConfiguration() public view {
        assertEq(governor.votingDelay(), 1 days);
        assertEq(governor.votingPeriod(), 7 days);
        assertEq(governor.proposalThreshold(), 1e18);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function testFuzz_VotingPower(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1_000_000e18));
        address delegatee = address(0xF00D);

        token.mint(delegatee, amount);
        vm.prank(delegatee);
        token.delegate(delegatee);

        assertEq(token.getVotes(delegatee), amount);
    }

    function _parameterProposal(uint256 value)
        private
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        description = "Change protocol parameter";

        targets[0] = address(settings);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(ProtocolSettings.changeParameter, (value));
    }

    function _proposeFrom(
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) private returns (uint256 proposalId) {
        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _passAndExecute(
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) private {
        uint256 proposalId = _proposeFrom(proposer, targets, values, calldatas, description);

        _advanceBlocks(governor.votingDelay() + 1);
        vm.prank(voter);
        governor.castVote(proposalId, 1);

        _advanceBlocks(governor.votingPeriod() + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function _advanceBlocks(uint256 blocks_) private {
        vm.roll(block.number + blocks_);
    }
}
