// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Errors} from "../libraries/Errors.sol";

/**
 * @title GovernanceToken
 * @notice UUPS upgradeable ERC20 token with voting capabilities
 * @dev Implements ERC20Votes for governance participation
 */
contract GovernanceToken is
    Initializable,
    UUPSUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    OwnableUpgradeable
{
    /// @custom:storage-location erc7201:defi.protocol.governance.token
    struct GovernanceTokenStorage {
        uint256 version;
        uint256 maxSupply;
        address minter;
    }

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.governance.token")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x5d8f2b3e1a9c7f4d6e0b8a5c2f1e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3900;

    function _getStorage() private pure returns (GovernanceTokenStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    /// @notice Emitted when the minter is updated
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);

    /// @notice Modifier to restrict minting to authorized minter
    modifier onlyMinter() {
        GovernanceTokenStorage storage $ = _getStorage();
        if (msg.sender != $.minter && msg.sender != owner()) {
            revert Errors.Unauthorized();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the governance token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param owner_ Owner address
     * @param maxSupply_ Maximum supply cap
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_,
        uint256 maxSupply_
    ) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();
        if (maxSupply_ == 0) revert Errors.ZeroAmount();

        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __ERC20Votes_init();
        __Ownable_init(owner_);

        GovernanceTokenStorage storage $ = _getStorage();
        $.version = 1;
        $.maxSupply = maxSupply_;
        $.minter = owner_;
    }

    /**
     * @notice Mints tokens to a recipient
     * @param to The recipient address
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) external onlyMinter {
        if (to == address(0)) revert Errors.ZeroAddress();

        GovernanceTokenStorage storage $ = _getStorage();
        if (totalSupply() + amount > $.maxSupply) revert Errors.InvalidAmount();

        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from the caller
     * @param amount The amount to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burns tokens from an account with allowance
     * @param account The account to burn from
     * @param amount The amount to burn
     */
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /**
     * @notice Sets the minter address
     * @param newMinter The new minter address
     */
    function setMinter(address newMinter) external onlyOwner {
        GovernanceTokenStorage storage $ = _getStorage();
        address oldMinter = $.minter;
        $.minter = newMinter;
        emit MinterUpdated(oldMinter, newMinter);
    }

    /**
     * @notice Returns the minter address
     * @return The minter address
     */
    function minter() external view returns (address) {
        return _getStorage().minter;
    }

    /**
     * @notice Returns the maximum supply
     * @return The max supply
     */
    function maxSupply() external view returns (uint256) {
        return _getStorage().maxSupply;
    }

    /**
     * @notice Returns the contract version
     * @return The version number
     */
    function version() external view returns (uint256) {
        return _getStorage().version;
    }

    /**
     * @notice Returns the clock mode for voting
     * @return The clock mode string
     */
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @notice Returns the current clock value (timestamp)
     * @return The current timestamp
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // Required overrides

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._update(from, to, value);
    }

    function nonces(
        address owner_
    ) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner_);
    }

    /**
     * @notice Authorizes an upgrade
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        if (newImplementation == address(0)) revert Errors.InvalidImplementation();
        _getStorage().version++;
    }
}
