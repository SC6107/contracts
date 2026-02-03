// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {JumpRateModel} from "../src/lending/JumpRateModel.sol";
import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {LendingToken} from "../src/lending/LendingToken.sol";
import {Comptroller} from "../src/lending/Comptroller.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {LiquidityMining} from "../src/mining/LiquidityMining.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title DeployProtocol
 * @notice Deploys the entire DeFi protocol suite with proxies
 */
contract DeployProtocol is Script {
    // Deployment addresses
    address public jumpRateModel;
    address public priceOracle;
    address public comptroller;
    address public governanceToken;
    address public liquidityMining;
    address public protocolTimelock;
    address public protocolGovernor;

    // Configuration
    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18; // 1:1 initially
    uint256 public constant GOV_TOKEN_MAX_SUPPLY = 100_000_000e18; // 100M tokens
    uint256 public constant REWARDS_DURATION = 30 days;
    uint256 public constant TIMELOCK_DELAY = 24 hours;
    uint48 public constant VOTING_DELAY = 1 days;
    uint32 public constant VOTING_PERIOD = 1 weeks;
    uint256 public constant PROPOSAL_THRESHOLD = 100_000e18; // 100k tokens
    uint256 public constant QUORUM_PERCENTAGE = 4; // 4%

    // Interest rate model parameters (per year, scaled by 1e18)
    uint256 public constant BASE_RATE_PER_YEAR = 0.02e18; // 2%
    uint256 public constant MULTIPLIER_PER_YEAR = 0.1e18; // 10%
    uint256 public constant JUMP_MULTIPLIER_PER_YEAR = 1e18; // 100%
    uint256 public constant KINK = 0.8e18; // 80% utilization

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy JumpRateModel (non-upgradeable)
        jumpRateModel = address(
            new JumpRateModel(BASE_RATE_PER_YEAR, MULTIPLIER_PER_YEAR, JUMP_MULTIPLIER_PER_YEAR, KINK)
        );
        console2.log("JumpRateModel deployed at:", jumpRateModel);

        // 2. Deploy PriceOracle (upgradeable)
        address priceOracleImpl = address(new PriceOracle());
        priceOracle = address(
            new ERC1967Proxy(
                priceOracleImpl,
                abi.encodeCall(PriceOracle.initialize, (deployer))
            )
        );
        console2.log("PriceOracle deployed at:", priceOracle);

        // 3. Deploy Comptroller (upgradeable)
        address comptrollerImpl = address(new Comptroller());
        comptroller = address(
            new ERC1967Proxy(
                comptrollerImpl,
                abi.encodeCall(Comptroller.initialize, (deployer, priceOracle))
            )
        );
        console2.log("Comptroller deployed at:", comptroller);

        // 4. Deploy GovernanceToken (upgradeable)
        address govTokenImpl = address(new GovernanceToken());
        governanceToken = address(
            new ERC1967Proxy(
                govTokenImpl,
                abi.encodeCall(
                    GovernanceToken.initialize,
                    ("Protocol Governance Token", "GOV", deployer, GOV_TOKEN_MAX_SUPPLY)
                )
            )
        );
        console2.log("GovernanceToken deployed at:", governanceToken);

        // 5. Deploy ProtocolTimelock (upgradeable)
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = deployer; // Temporary, will be updated after governor deployment
        executors[0] = address(0); // Anyone can execute

        address timelockImpl = address(new ProtocolTimelock());
        protocolTimelock = address(
            new ERC1967Proxy(
                timelockImpl,
                abi.encodeCall(ProtocolTimelock.initialize, (TIMELOCK_DELAY, proposers, executors, deployer))
            )
        );
        console2.log("ProtocolTimelock deployed at:", protocolTimelock);

        // 6. Deploy ProtocolGovernor (upgradeable)
        address governorImpl = address(new ProtocolGovernor());
        protocolGovernor = address(
            new ERC1967Proxy(
                governorImpl,
                abi.encodeCall(
                    ProtocolGovernor.initialize,
                    (
                        IVotes(governanceToken),
                        TimelockControllerUpgradeable(payable(protocolTimelock)),
                        VOTING_DELAY,
                        VOTING_PERIOD,
                        PROPOSAL_THRESHOLD,
                        QUORUM_PERCENTAGE
                    )
                )
            )
        );
        console2.log("ProtocolGovernor deployed at:", protocolGovernor);

        // 7. Grant proposer role to governor
        bytes32 proposerRole = TimelockControllerUpgradeable(payable(protocolTimelock)).PROPOSER_ROLE();
        bytes32 cancellerRole = TimelockControllerUpgradeable(payable(protocolTimelock)).CANCELLER_ROLE();
        TimelockControllerUpgradeable(payable(protocolTimelock)).grantRole(proposerRole, protocolGovernor);
        TimelockControllerUpgradeable(payable(protocolTimelock)).grantRole(cancellerRole, protocolGovernor);
        console2.log("Governor granted proposer and canceller roles");

        vm.stopBroadcast();

        // Log summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("JumpRateModel:", jumpRateModel);
        console2.log("PriceOracle:", priceOracle);
        console2.log("Comptroller:", comptroller);
        console2.log("GovernanceToken:", governanceToken);
        console2.log("ProtocolTimelock:", protocolTimelock);
        console2.log("ProtocolGovernor:", protocolGovernor);
    }

    /**
     * @notice Deploys a LendingToken for a specific asset
     * @param underlying The underlying asset address
     * @param name Token name
     * @param symbol Token symbol
     * @return The deployed LendingToken proxy address
     */
    function deployLendingToken(
        address underlying,
        string memory name,
        string memory symbol
    ) external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address lendingTokenImpl = address(new LendingToken());
        address lendingToken = address(
            new ERC1967Proxy(
                lendingTokenImpl,
                abi.encodeCall(
                    LendingToken.initialize,
                    (underlying, comptroller, jumpRateModel, INITIAL_EXCHANGE_RATE, name, symbol, deployer)
                )
            )
        );

        console2.log("LendingToken deployed at:", lendingToken);

        vm.stopBroadcast();

        return lendingToken;
    }

    /**
     * @notice Deploys a LiquidityMining contract for a specific dToken
     * @param stakingToken The staking token (dToken) address
     * @return The deployed LiquidityMining proxy address
     */
    function deployLiquidityMining(address stakingToken) external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        address miningImpl = address(new LiquidityMining());
        address mining = address(
            new ERC1967Proxy(
                miningImpl,
                abi.encodeCall(
                    LiquidityMining.initialize,
                    (deployer, stakingToken, governanceToken, REWARDS_DURATION)
                )
            )
        );

        console2.log("LiquidityMining deployed at:", mining);

        vm.stopBroadcast();

        return mining;
    }
}
