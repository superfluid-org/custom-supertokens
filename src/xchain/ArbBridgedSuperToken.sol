// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

import { IArbToken } from "./interfaces/IArbToken.sol";
import { BridgedSuperTokenProxy, IBridgedSuperToken, IXERC20 } from "./BridgedSuperToken.sol";

/**
 * @title Extends BridgedSuperTokenProxy with the interface required by the Arbitrum Bridge
 */
contract ArbBridgedSuperTokenProxy is BridgedSuperTokenProxy, IArbToken {
    address internal immutable _NATIVE_BRIDGE;
    address internal immutable _REMOTE_TOKEN;

    // initializes the immutables and sets max limit for the native bridge
    constructor(address nativeBridge_, address remoteToken_) {
        _NATIVE_BRIDGE = nativeBridge_;
        _REMOTE_TOKEN = remoteToken_;
        // the native bridge gets (de facto) unlimited mint/burn allowance
        setLimits(nativeBridge_, _MAX_LIMIT, _MAX_LIMIT);
    }

    // ===== IArbToken =====

    /// @inheritdoc IArbToken
    function bridgeMint(address account, uint256 amount) external {
        return super.mint(account, amount);
    }

    /// @inheritdoc IArbToken
    function bridgeBurn(address account, uint256 amount) external {
        return super.burn(account, amount);
    }

    /// @inheritdoc IArbToken
    function l1Address() external view returns (address) {
        return _REMOTE_TOKEN;
    }
}

interface IArbBridgedSuperToken is IBridgedSuperToken, IArbToken { }