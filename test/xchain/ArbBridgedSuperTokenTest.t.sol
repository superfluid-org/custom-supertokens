// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ArbBridgedSuperTokenProxy, IArbBridgedSuperToken, IBridgedSuperToken, IArbToken } from "../../src/xchain/ArbBridgedSuperToken.sol";
import { BridgedSuperTokenTest } from "./BridgedSuperTokenTest.t.sol";

contract ArbBridgedSuperTokenTest is BridgedSuperTokenTest {
    address internal _nativeBridge = address(99);
    address internal _remoteToken = address(98);
    IArbBridgedSuperToken internal _arbToken;

    function _deployToken(address owner) internal override {
        // deploy proxy
        ArbBridgedSuperTokenProxy proxy = new ArbBridgedSuperTokenProxy(_nativeBridge, _remoteToken);
        // initialize proxy
        proxy.initialize(sf.superTokenFactory, "Test Token", "TT", _owner, 1000);
        proxy.transferOwnership(owner);

        _arbToken = IArbBridgedSuperToken(address(proxy));
        _xerc20 = IBridgedSuperToken(_arbToken);
    }

    function testMintByNativeBridge(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max / 2);

        vm.prank(_nativeBridge);
        _arbToken.bridgeMint(_user, _amount);

        assertEq(_xerc20.balanceOf(_user), _amount);
    }

    function testBurnByNativeBridge(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max / 2);

        vm.prank(_nativeBridge);
        _arbToken.bridgeMint(_user, _amount);

        vm.prank(_user);
        _arbToken.approve(_nativeBridge, _amount);

        vm.prank(_nativeBridge);
        _arbToken.bridgeBurn(_user, _amount);

        assertEq(_xerc20.balanceOf(_user), 0);
    }
}