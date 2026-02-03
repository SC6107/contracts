// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

import {GovernanceToken} from "../../src/governance/GovernanceToken.sol";
import {ProtocolGovernor} from "../../src/governance/ProtocolGovernor.sol";
import {ProtocolTimelock} from "../../src/governance/ProtocolTimelock.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract GovernanceTest is Test {
    GovernanceToken public govToken;
    ProtocolGovernor public governor;
    ProtocolTimelock public timelock;

    address public owner = address(1);
    address public proposer = address(2);
    address public voter1 = address(3);
    address public voter2 = address(4);
    address public voter3 = address(5);

    uint256 constant MAX_SUPPLY = 100_000_000e18;
    uint256 constant VOTING_DELAY = 1 days;
    uint256 constant VOTING_PERIOD = 1 weeks;
    uint256 constant PROPOSAL_THRESHOLD = 100_000e18;
    uint256 constant QUORUM_PERCENTAGE = 4;
    uint256 constant TIMELOCK_DELAY = 24 hours;

    function setUp() public {
        // Deploy governance token
        GovernanceToken tokenImpl = new GovernanceToken();
        govToken = GovernanceToken(
            address(
                new ERC1967Proxy(
                    address(tokenImpl),
                    abi.encodeCall(GovernanceToken.initialize, ("Protocol Gov", "GOV", owner, MAX_SUPPLY))
                )
            )
        );

        // Deploy timelock
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = owner;
        executors[0] = address(0); // Anyone can execute

        ProtocolTimelock timelockImpl = new ProtocolTimelock();
        timelock = ProtocolTimelock(
            payable(
                address(
                    new ERC1967Proxy(
                        address(timelockImpl),
                        abi.encodeCall(
                            ProtocolTimelock.initialize,
                            (TIMELOCK_DELAY, proposers, executors, owner)
                        )
                    )
                )
            )
        );

        // Deploy governor
        ProtocolGovernor governorImpl = new ProtocolGovernor();
        governor = ProtocolGovernor(
            payable(
                address(
                    new ERC1967Proxy(
                        address(governorImpl),
                        abi.encodeCall(
                            ProtocolGovernor.initialize,
                            (
                                IVotes(address(govToken)),
                                TimelockControllerUpgradeable(payable(address(timelock))),
                                uint48(VOTING_DELAY),
                                uint32(VOTING_PERIOD),
                                PROPOSAL_THRESHOLD,
                                QUORUM_PERCENTAGE
                            )
                        )
                    )
                )
            )
        );

        // Grant proposer role to governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        vm.startPrank(owner);
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(cancellerRole, address(governor));
        vm.stopPrank();

        // Distribute tokens
        vm.startPrank(owner);
        govToken.mint(proposer, PROPOSAL_THRESHOLD);
        govToken.mint(voter1, 1_000_000e18);
        govToken.mint(voter2, 2_000_000e18);
        govToken.mint(voter3, 1_000_000e18);
        vm.stopPrank();

        // Delegate votes
        vm.prank(proposer);
        govToken.delegate(proposer);

        vm.prank(voter1);
        govToken.delegate(voter1);

        vm.prank(voter2);
        govToken.delegate(voter2);

        vm.prank(voter3);
        govToken.delegate(voter3);

        // Advance block to ensure delegation is active
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function test_TokenInitialization() public view {
        assertEq(govToken.name(), "Protocol Gov");
        assertEq(govToken.symbol(), "GOV");
        assertEq(govToken.maxSupply(), MAX_SUPPLY);
        assertEq(govToken.version(), 1);
    }

    function test_TokenMint() public {
        vm.prank(owner);
        govToken.mint(address(100), 1000e18);

        assertEq(govToken.balanceOf(address(100)), 1000e18);
    }

    function test_TokenMint_ExceedsMaxSupply() public {
        vm.prank(owner);
        vm.expectRevert(Errors.InvalidAmount.selector);
        govToken.mint(address(100), MAX_SUPPLY + 1);
    }

    function test_TokenDelegation() public view {
        assertEq(govToken.getVotes(voter1), 1_000_000e18);
        assertEq(govToken.getVotes(voter2), 2_000_000e18);
    }

    function test_GovernorInitialization() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.upgradeVersion(), 1);
    }

    function test_TimelockInitialization() public view {
        assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
        assertEq(timelock.version(), 1);
    }

    function test_CreateProposal() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(100)));

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Set new minter");

        assertGt(proposalId, 0);

        // Check proposal state is Pending
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

    function test_CreateProposal_BelowThreshold() public {
        address lowHolder = address(100);
        vm.prank(owner);
        govToken.mint(lowHolder, 1000e18);

        vm.prank(lowHolder);
        govToken.delegate(lowHolder);

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(100)));

        vm.prank(lowHolder);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    function test_VoteOnProposal() public {
        // Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(100)));

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Set new minter");

        // Advance past voting delay
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // Vote
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        vm.prank(voter2);
        governor.castVote(proposalId, 1); // For

        // Check state is Active
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // Check votes
        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 3_000_000e18); // voter1 + voter2
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_FullGovernanceFlow() public {
        // Transfer ownership of govToken to timelock so it can call setMinter
        vm.prank(owner);
        govToken.transferOwnership(address(timelock));

        // 1. Create proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(timelock)));

        // Record initial timestamp
        uint256 startTime = block.timestamp;

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Set timelock as minter");

        // 2. Advance past voting delay (timestamp-based)
        uint256 votingStartTime = startTime + VOTING_DELAY + 1;
        vm.warp(votingStartTime);

        // 3. Vote
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        vm.prank(voter3);
        governor.castVote(proposalId, 1);

        // 4. Advance past voting period
        uint256 votingEndTime = votingStartTime + VOTING_PERIOD + 1;
        vm.warp(votingEndTime);

        // Check state is Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // 5. Queue proposal
        bytes32 descriptionHash = keccak256(bytes("Set timelock as minter"));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Check state is Queued
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // 6. Advance past timelock delay
        uint256 executeTime = votingEndTime + TIMELOCK_DELAY + 1;
        vm.warp(executeTime);

        // 7. Execute proposal
        governor.execute(targets, values, calldatas, descriptionHash);

        // Check state is Executed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        // Verify effect
        assertEq(govToken.minter(), address(timelock));
    }

    function test_ProposalDefeated() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(100)));

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Should be defeated");

        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // Vote against
        vm.prank(voter1);
        governor.castVote(proposalId, 0); // Against

        vm.prank(voter2);
        governor.castVote(proposalId, 0); // Against

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Check state is Defeated
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_QuorumNotReached() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(govToken);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovernanceToken.setMinter, (address(100)));

        vm.prank(proposer);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Quorum not met");

        vm.warp(block.timestamp + VOTING_DELAY + 1);

        // Only one voter with small amount votes
        vm.prank(proposer);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Check state is Defeated (quorum not reached)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_TokenBurn() public {
        uint256 burnAmount = 500_000e18;

        vm.prank(voter1);
        govToken.burn(burnAmount);

        assertEq(govToken.balanceOf(voter1), 500_000e18);
    }

    function test_TokenTransferUpdatesVotes() public {
        uint256 transferAmount = 500_000e18;

        uint256 voter1VotesBefore = govToken.getVotes(voter1);

        vm.prank(voter1);
        govToken.transfer(voter2, transferAmount);

        // Need to delegate again or votes are lost
        assertEq(govToken.getVotes(voter1), voter1VotesBefore - transferAmount);
    }
}
