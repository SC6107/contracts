// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ReentrancyGuardStorage
 * @notice ERC-7201 namespaced storage for reentrancy guard
 * @dev Custom implementation since OZ v5 doesn't have ReentrancyGuardUpgradeable
 */
library ReentrancyGuardStorage {
    /// @custom:storage-location erc7201:defi.protocol.reentrancy.guard
    struct Layout {
        uint256 status;
    }

    uint256 internal constant NOT_ENTERED = 1;
    uint256 internal constant ENTERED = 2;

    // keccak256(abi.encode(uint256(keccak256("defi.protocol.reentrancy.guard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_LOCATION;
        assembly {
            l.slot := slot
        }
    }
}

/**
 * @title ReentrancyGuardUpgradeable
 * @notice Custom reentrancy guard for upgradeable contracts
 */
abstract contract ReentrancyGuardUpgradeable {
    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal {
        ReentrancyGuardStorage.Layout storage $ = ReentrancyGuardStorage.layout();
        $.status = ReentrancyGuardStorage.NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        ReentrancyGuardStorage.Layout storage $ = ReentrancyGuardStorage.layout();
        if ($.status == ReentrancyGuardStorage.ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        $.status = ReentrancyGuardStorage.ENTERED;
    }

    function _nonReentrantAfter() private {
        ReentrancyGuardStorage.layout().status = ReentrancyGuardStorage.NOT_ENTERED;
    }
}
