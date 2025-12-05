// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {
    ISuperTokenFactory,
    ISuperToken,
    IERC20Metadata
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { BridgedSuperTokenProxy, IBridgedSuperToken } from "../src/xchain/BridgedSuperToken.sol";
import { OPBridgedSuperTokenProxy, IOPBridgedSuperToken } from "../src/xchain/OPBridgedSuperToken.sol";
import { ArbBridgedSuperTokenProxy, IArbBridgedSuperToken } from "../src/xchain/ArbBridgedSuperToken.sol";
import { HomeERC20 } from "../src/xchain/HomeERC20.sol";
import { PureSuperTokenProxy, IPureSuperToken } from "../src/PureSuperToken.sol";
import { CustomERC20WrapperProxy, ICustomERC20Wrapper } from "../src/CustomERC20Wrapper.sol";

/// abstract base contract to avoid code duplication
abstract contract DeployBase is Script {
    uint256 deployerPrivKey;
    address superTokenFactoryAddr;
    address owner;
    string name;
    string symbol;
    uint256 initialSupply;

    function _loadEnv() internal virtual {
        // Support both private key and Foundry wallet account (via --account flag)
        // If PRIVKEY is set, use it; otherwise use default account (from --account flag)
        deployerPrivKey = vm.envOr("PRIVKEY", uint256(0));
        
        // factory
        superTokenFactoryAddr = vm.envOr("SUPERTOKEN_FACTORY", address(0));
        owner = vm.envAddress("OWNER");
        name = vm.envString("NAME");
        symbol = vm.envString("SYMBOL");
        initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(0));
    }

    /// @notice Starts broadcast using private key or default account (from --account flag)
    function _startBroadcast() internal {
        if (deployerPrivKey != 0) {
            vm.startBroadcast(deployerPrivKey);
        } else {
            vm.startBroadcast();
        }
    }
    

    /// @notice Verifies that 
    /// - the proxy's implementation matches the canonical SuperToken implementation.
    /// This gives more reassurance that the proxy wasn't tampered with by a fruntrunner.
    /// The proxy implementation used here shouldn't be susceptible to this - meaning, "initialize()" is expected
    /// to revert in case of frontrunning, because not relying on implementation contract logic
    /// for setting the pointer. But it doesn't hurt to be extra cautious.
    /// See https://dedaub.com/blog/the-cpimp-attack-an-insanely-far-reaching-vulnerability-successfully-mitigated/
    /// - the SuperToken has been initialized as intended
    /// @param proxy The proxy contract address to verify
    function _verifyDeployment(address proxy) internal view {
        bytes32 EIP_1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address proxyImpl = address(uint160(uint256(vm.load(proxy, EIP_1967_IMPLEMENTATION_SLOT))));
        address canonicalImpl = address((ISuperTokenFactory(superTokenFactoryAddr)).getSuperTokenLogic());
        require(
            proxyImpl == canonicalImpl,
            "unexpected implementation set in proxy, doesn't match canonical SuperToken implementation"
        );
        ISuperToken token = ISuperToken(proxy);
        require(keccak256(abi.encodePacked(token.name())) == keccak256(abi.encodePacked(name)), "name mismatch");
        require(keccak256(abi.encodePacked(token.symbol())) == keccak256(abi.encodePacked(symbol)), "symbol mismatch");
        require(token.totalSupply() == initialSupply, "totalSupply mismatch");
        require(token.balanceOf(owner) == initialSupply, "balanceOf mismatch");
    }
}

/// deploys an instance of HomeERC20
contract DeployL1Token is DeployBase {
    function run() external {
        _loadEnv();

        _startBroadcast();

        // log params
        console.log("Deploying ERC20 with params:");
        console.log("  name:", name);
        console.log("  symbol:", symbol);
        console.log("  initialSupply:", initialSupply);
        console.log("  owner:", owner);

        // since the token is permissionless and non-upgradable, the "owner" doesn't
        // own the contract, just the initial supply
        HomeERC20 erc20 = new HomeERC20(name, symbol, owner, initialSupply);
        console.log("ERC20 deployed at", address(erc20));

        vm.stopBroadcast();
    }
}

/// Factory for atomic BridgedSuperTokenProxy deployment + initialization in one transaction.
contract BridgedSuperTokenFactory {
    BridgedSuperTokenProxy public proxy;
    constructor(
        address superTokenFactoryAddr,
        string memory name,
        string memory symbol,
        address owner,
        uint256 initialSupply
    ) {
        proxy = new BridgedSuperTokenProxy();
        proxy.initialize(
            ISuperTokenFactory(superTokenFactoryAddr),
            name,
            symbol,
            owner,
            initialSupply
        );
        proxy.transferOwnership(owner);
    }
}

/// deploys and initializes an instance of BridgedSuperTokenProxy
contract DeployL2Token is DeployBase {
    function run() external {
        _loadEnv();

        _startBroadcast();

        BridgedSuperTokenFactory factory = new BridgedSuperTokenFactory(
            superTokenFactoryAddr,
            name,
            symbol,
            owner,
            initialSupply
        );
        console.log("BridgedSuperTokenProxy deployed at", address(factory.proxy()));

        vm.stopBroadcast();

        _verifyDeployment(address(factory.proxy()));
    }
}

/// Factory for atomic OPBridgedSuperTokenProxy deployment + initialization in one transaction.
contract OPBridgedSuperTokenFactory {
    OPBridgedSuperTokenProxy public proxy;
    constructor(
        address nativeBridge,
        address remoteToken,
        address superTokenFactoryAddr,
        string memory name,
        string memory symbol,
        address owner,
        uint256 initialSupply
    ) {
        proxy = new OPBridgedSuperTokenProxy(nativeBridge, remoteToken);
        proxy.initialize(
            ISuperTokenFactory(superTokenFactoryAddr),
            name,
            symbol,
            owner,
            initialSupply
        );
        proxy.transferOwnership(owner);
    }
}

/// deploys and initializes an instance of OPBridgedSuperTokenProxy
contract DeployOPToken is DeployBase {
    function run() external {
        _loadEnv();

        _startBroadcast();

        address nativeBridge = vm.envAddress("NATIVE_BRIDGE");
        address remoteToken = vm.envAddress("REMOTE_TOKEN");

        OPBridgedSuperTokenFactory factory = new OPBridgedSuperTokenFactory(
            nativeBridge,
            remoteToken,
            superTokenFactoryAddr,
            name,
            symbol,
            owner,
            initialSupply
        );
        console.log("OPBridgedSuperTokenProxy deployed at", address(factory.proxy()));

        vm.stopBroadcast();

        _verifyDeployment(address(factory.proxy()));
    }
}

/// Factory for atomic ArbBridgedSuperTokenProxy deployment + initialization in one transaction.
contract ArbBridgedSuperTokenFactory {
    ArbBridgedSuperTokenProxy public proxy;
    constructor(
        address nativeBridge,
        address remoteToken,
        address superTokenFactoryAddr,
        string memory name,
        string memory symbol,
        address owner,
        uint256 initialSupply
    ) {
        proxy = new ArbBridgedSuperTokenProxy(nativeBridge, remoteToken);
        proxy.initialize(
            ISuperTokenFactory(superTokenFactoryAddr),
            name,
            symbol,
            owner,
            initialSupply
        );
        proxy.transferOwnership(owner);
    }
}

/// deploys and initializes an instance of ArbBridgedSuperTokenProxy
contract DeployArbToken is DeployBase {
    function run() external {
        _loadEnv();
        
        _startBroadcast();

        address nativeBridge = vm.envAddress("NATIVE_BRIDGE");
        address remoteToken = vm.envAddress("REMOTE_TOKEN");

        ArbBridgedSuperTokenFactory factory = new ArbBridgedSuperTokenFactory(
            nativeBridge,
            remoteToken,
            superTokenFactoryAddr,
            name,
            symbol,
            owner,
            initialSupply
        );
        console.log("ArbBridgedSuperTokenProxy deployed at", address(factory.proxy()));

        vm.stopBroadcast();

        _verifyDeployment(address(factory.proxy()));
    }
}

/// Factory for atomic proxy deployment + initialization in one transaction.
contract PureSuperTokenFactory {
    PureSuperTokenProxy public proxy;
    constructor(
        address superTokenFactoryAddr,
        string memory name,
        string memory symbol,
        address owner,
        uint256 initialSupply
    ) {
        proxy = new PureSuperTokenProxy();
        PureSuperTokenProxy(proxy).initialize(
            ISuperTokenFactory(superTokenFactoryAddr),
            name,
            symbol,
            owner,
            initialSupply
        );
    }
}

/// deploys and initializes an instance of PureSuperTokenProxy
contract DeployPureSuperToken is DeployBase {
    function run() external {
        _loadEnv();

        _startBroadcast();

        // log params
        console.log("Deploying PureSuperToken with params:");
        console.log("  name:", name);
        console.log("  symbol:", symbol);
        console.log("  initialSupply:", initialSupply);
        console.log("  receiver:", owner);

        // PureSuperTokenProxy proxy = new PureSuperTokenProxy();
        // proxy.initialize(ISuperTokenFactory(superTokenFactoryAddr), name, symbol, owner, initialSupply);
        PureSuperTokenFactory factory = new PureSuperTokenFactory(
            superTokenFactoryAddr,
            name,
            symbol,
            owner,
            initialSupply
        );
        console.log("PureSuperTokenProxy deployed at", address(factory.proxy()));

        vm.stopBroadcast();

        _verifyDeployment(address(factory.proxy()));
    }
}

/// Factory for atomic CustomERC20WrapperProxy deployment + initialization in one transaction.
contract CustomERC20WrapperFactory {
    CustomERC20WrapperProxy public proxy;
    constructor(
        address underlyingTokenAddr,
        address superTokenFactoryAddr,
        string memory name,
        string memory symbol
    ) {
        proxy = new CustomERC20WrapperProxy();
        proxy.initialize(
            IERC20Metadata(underlyingTokenAddr),
            ISuperTokenFactory(superTokenFactoryAddr),
            name,
            symbol
        );
    }
}

/// deploys and initializes an instance of CustomERC20WrapperProxy
contract DeployCustomERC20Wrapper is DeployBase {
    function run() external {
        _loadEnv();

        address underlyingTokenAddr = vm.envAddress("UNDERLYING_TOKEN");

        _startBroadcast();

        // log params
        console.log("Deploying CustomERC20Wrapper with params:");
        console.log("  name:", name);
        console.log("  symbol:", symbol);
        console.log("  underlyingToken:", underlyingTokenAddr);

        CustomERC20WrapperFactory factory = new CustomERC20WrapperFactory(
            underlyingTokenAddr,
            superTokenFactoryAddr,
            name,
            symbol
        );
        console.log("CustomERC20WrapperProxy deployed at", address(factory.proxy()));

        vm.stopBroadcast();

        _verifyDeployment(address(factory.proxy()));
    }
}
