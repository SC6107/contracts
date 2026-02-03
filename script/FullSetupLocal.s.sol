// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {JumpRateModel} from "../src/lending/JumpRateModel.sol";
import {PriceOracle} from "../src/oracle/PriceOracle.sol";
import {LendingToken} from "../src/lending/LendingToken.sol";
import {Comptroller} from "../src/lending/Comptroller.sol";
import {GovernanceToken} from "../src/governance/GovernanceToken.sol";
import {ProtocolTimelock} from "../src/governance/ProtocolTimelock.sol";
import {ProtocolGovernor} from "../src/governance/ProtocolGovernor.sol";
import {LiquidityMining} from "../src/mining/LiquidityMining.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockPriceFeed} from "../test/mocks/MockPriceFeed.sol";

/**
 * @title FullSetupLocal
 * @notice Local-only setup: mocks + oracle + comptroller + lending tokens + governance + mining
 * @dev Comptroller flow (interact directly with LendingToken markets)
 */
contract FullSetupLocal is Script {
    // Token config
    uint8 internal constant TOKEN_DECIMALS = 18;
    uint256 internal constant INITIAL_EXCHANGE_RATE = 1e18; // 1:1

    // Mock prices (8 decimals)
    int256 internal constant USDC_PRICE = 1e8; // $1
    int256 internal constant WETH_PRICE = 2000e8; // $2000

    // Collateral factors (WAD)
    uint256 internal constant USDC_COLLATERAL_FACTOR = 0.75e18;
    uint256 internal constant WETH_COLLATERAL_FACTOR = 0.8e18;

    // Interest rate model parameters (per year, WAD)
    uint256 internal constant BASE_RATE_PER_YEAR = 0.02e18; // 2%
    uint256 internal constant MULTIPLIER_PER_YEAR = 0.1e18; // 10%
    uint256 internal constant JUMP_MULTIPLIER_PER_YEAR = 1e18; // 100%
    uint256 internal constant KINK = 0.8e18; // 80% utilization

    // Governance / mining config
    uint256 internal constant GOV_TOKEN_MAX_SUPPLY = 100_000_000e18;
    uint256 internal constant REWARDS_DURATION = 30 days;
    uint256 internal constant TIMELOCK_DELAY = 1 days;
    uint48 internal constant VOTING_DELAY = 1 days;
    uint32 internal constant VOTING_PERIOD = 1 weeks;
    uint256 internal constant PROPOSAL_THRESHOLD = 100_000e18;
    uint256 internal constant QUORUM_PERCENTAGE = 4;

    // Mint amount for test accounts
    uint256 internal constant INITIAL_BALANCE = 100_000e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Deploy mocks
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", TOKEN_DECIMALS);
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", TOKEN_DECIMALS);

        MockPriceFeed usdcFeed = new MockPriceFeed(USDC_PRICE, 8);
        MockPriceFeed wethFeed = new MockPriceFeed(WETH_PRICE, 8);

        // 2) Deploy PriceOracle proxy and configure feeds
        PriceOracle priceOracle = PriceOracle(
            address(
                new ERC1967Proxy(
                    address(new PriceOracle()),
                    abi.encodeCall(PriceOracle.initialize, (deployer))
                )
            )
        );
        priceOracle.setAssetSource(address(usdc), address(usdcFeed));
        priceOracle.setAssetSource(address(weth), address(wethFeed));

        // 3) Deploy interest rate model
        JumpRateModel interestRateModel = new JumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            KINK
        );

        // 4) Deploy Comptroller proxy
        Comptroller comptroller = Comptroller(
            address(
                new ERC1967Proxy(
                    address(new Comptroller()),
                    abi.encodeCall(Comptroller.initialize, (deployer, address(priceOracle)))
                )
            )
        );

        // 5) Deploy LendingToken markets (dUSDC, dWETH)
        LendingToken dUSDC = LendingToken(
            address(
                new ERC1967Proxy(
                    address(new LendingToken()),
                    abi.encodeCall(
                        LendingToken.initialize,
                        (address(usdc), address(comptroller), address(interestRateModel), INITIAL_EXCHANGE_RATE, "dUSDC", "dUSDC", deployer)
                    )
                )
            )
        );

        LendingToken dWETH = LendingToken(
            address(
                new ERC1967Proxy(
                    address(new LendingToken()),
                    abi.encodeCall(
                        LendingToken.initialize,
                        (address(weth), address(comptroller), address(interestRateModel), INITIAL_EXCHANGE_RATE, "dWETH", "dWETH", deployer)
                    )
                )
            )
        );

        // 6) List markets in Comptroller
        comptroller.supportMarket(address(dUSDC), USDC_COLLATERAL_FACTOR);
        comptroller.supportMarket(address(dWETH), WETH_COLLATERAL_FACTOR);

        // 7) Deploy governance token (proxy)
        GovernanceToken governanceToken = GovernanceToken(
            address(
                new ERC1967Proxy(
                    address(new GovernanceToken()),
                    abi.encodeCall(
                        GovernanceToken.initialize,
                        ("Protocol Governance Token", "GOV", deployer, GOV_TOKEN_MAX_SUPPLY)
                    )
                )
            )
        );

        // 8) Deploy timelock (proxy)
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = deployer; // temporary
        executors[0] = address(0); // anyone can execute

        ProtocolTimelock timelock = ProtocolTimelock(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new ProtocolTimelock()),
                        abi.encodeCall(ProtocolTimelock.initialize, (TIMELOCK_DELAY, proposers, executors, deployer))
                    )
                )
            )
        );

        // 9) Deploy governor (proxy)
        ProtocolGovernor governor = ProtocolGovernor(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new ProtocolGovernor()),
                        abi.encodeCall(
                            ProtocolGovernor.initialize,
                            (
                                IVotes(address(governanceToken)),
                                TimelockControllerUpgradeable(payable(address(timelock))),
                                VOTING_DELAY,
                                VOTING_PERIOD,
                                PROPOSAL_THRESHOLD,
                                QUORUM_PERCENTAGE
                            )
                        )
                    )
                )
            )
        );

        // 10) Grant governor roles on timelock
        bytes32 proposerRole = TimelockControllerUpgradeable(payable(address(timelock))).PROPOSER_ROLE();
        bytes32 cancellerRole = TimelockControllerUpgradeable(payable(address(timelock))).CANCELLER_ROLE();
        TimelockControllerUpgradeable(payable(address(timelock))).grantRole(proposerRole, address(governor));
        TimelockControllerUpgradeable(payable(address(timelock))).grantRole(cancellerRole, address(governor));

        // 11) Deploy liquidity mining (dUSDC + dWETH)
        LiquidityMining usdcMining = LiquidityMining(
            address(
                new ERC1967Proxy(
                    address(new LiquidityMining()),
                    abi.encodeCall(
                        LiquidityMining.initialize,
                        (deployer, address(dUSDC), address(governanceToken), REWARDS_DURATION)
                    )
                )
            )
        );
        LiquidityMining wethMining = LiquidityMining(
            address(
                new ERC1967Proxy(
                    address(new LiquidityMining()),
                    abi.encodeCall(
                        LiquidityMining.initialize,
                        (deployer, address(dWETH), address(governanceToken), REWARDS_DURATION)
                    )
                )
            )
        );

        // 12) Mint tokens to test accounts
        _mintToTestAccounts(usdc, deployer);
        _mintToTestAccounts(weth, deployer);

        vm.stopBroadcast();

        // Summary
        console2.log("\n=== Local Full Setup Summary ===");
        console2.log("USDC:", address(usdc));
        console2.log("WETH:", address(weth));
        console2.log("USDC Feed:", address(usdcFeed));
        console2.log("WETH Feed:", address(wethFeed));
        console2.log("PriceOracle:", address(priceOracle));
        console2.log("Comptroller:", address(comptroller));
        console2.log("InterestRateModel:", address(interestRateModel));
        console2.log("dUSDC:", address(dUSDC));
        console2.log("dWETH:", address(dWETH));
        console2.log("GovernanceToken:", address(governanceToken));
        console2.log("ProtocolTimelock:", address(timelock));
        console2.log("ProtocolGovernor:", address(governor));
        console2.log("USDC Mining:", address(usdcMining));
        console2.log("WETH Mining:", address(wethMining));
    }

    function _mintToTestAccounts(MockERC20 token, address deployer) internal {
        address[] memory accounts = new address[](6);
        accounts[0] = deployer;
        accounts[1] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // anvil account 0
        accounts[2] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // anvil account 1
        accounts[3] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // anvil account 2
        accounts[4] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // anvil account 3
        accounts[5] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // anvil account 4

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (account == address(0)) continue;
            if (account != deployer && _isDuplicate(account, accounts, i)) continue;
            token.mint(account, INITIAL_BALANCE);
        }
    }

    function _isDuplicate(address account, address[] memory accounts, uint256 index) internal pure returns (bool) {
        for (uint256 i = 0; i < index; i++) {
            if (accounts[i] == account) return true;
        }
        return false;
    }
}
