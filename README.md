# Custom Super Tokens

This repository shows how to implement custom SuperTokens.

A custom SuperToken contract typically consists of:
* (immutable) proxy contract with custom logic
* (upgradable) logic contract containing ERC20 and SuperToken functionality

By convention, SuperToken contracts are instances of [UUPSProxy](https://github.com/superfluid-finance/protocol-monorepo/blob/dev/packages/ethereum-contracts/contracts/upgradability/UUPSProxy.sol).
A _custom_ Super Token has custom logic added to this proxy contract.

[PureSuperToken.sol](src/PureSuperToken.sol) is the simplest variant of a custom SuperToken. It's a _Pure SuperToken_ (no underlying ERC20) which has its supply minted on creation.

[PureSuperTokenPermit.sol](src/PureSuperTokenPermit.sol) is is a Pure SuperToken which also implements IERC20Permit.

[CustomERC20WrapperProxy.sol](src/CustomERC20WrapperProxy.sol) shows how a _Wrapper SuperToken_ (has an unerlying ERC20) could be customized.

[xchain](src/xchain) contains more advanced variants of Custom SuperTokens, suited for cross-chain deployments (e.g. bridging ERC20 <-> SuperToken). See [the dedicated section](#bridging-with-xerc20) for more.

## Setup

To set up the repo for development, start by cloning the repo

```bash
git clone https://github.com/superfluid-finance/custom-supertokens
cd custom-supertokens
```

## Installing Foundry

Make sure you have installed Foundry. If you don't have Foundry on your development environment, please refer to [Foundry Book](https://book.getfoundry.sh/).

## Install dependencies

Once Foundry has been installed, you can run the following command to install dependencies

```bash
forge install
```
This command will install the `@superfluid-finance` packages, and the `@openzeppelin-contracts (v4.9.3)` packages, in addition to to `forge-std`.

## Create your Custom Super Token

As an example of creating your own Custom Super Token, we can take a look at the `PureSuperToken.sol` contract.

```solidity
contract PureSuperTokenProxy is CustomSuperTokenBase, UUPSProxy {
	// This shall be invoked exactly once after deployment, needed for the token contract to become operational.
	function initialize(
		ISuperTokenFactory factory,
		string memory name,
		string memory symbol,
		address receiver,
		uint256 initialSupply
	) external {
		// This call to the factory invokes `UUPSProxy.initialize`, which connects the proxy to the canonical SuperToken implementation.
		// It also emits an event which facilitates discovery of this token.
		ISuperTokenFactory(factory).initializeCustomSuperToken(address(this));

		// This initializes the token storage and sets the `initialized` flag of OpenZeppelin Initializable.
		// This makes sure that it will revert if invoked more than once.
		ISuperToken(address(this)).initialize(
			IERC20(address(0)),
			18,
			name,
			symbol
		);

		// This mints the specified initial supply to the specified receiver.
		ISuperToken(address(this)).selfMint(receiver, initialSupply, "");
	}
}
```

This contract simply creates a new `UUPSProxy` with a custom `initialize` method.
This method calls `SuperTokenFactory.initializeCustomSuperToken` (which emits events facilitating discovery of the SuperToken), then mints the full supply of the token to the `receiver`.

For more information on the creation of Custom Super Tokens, please refer to the [Technical Documentation](https://docs.superfluid.finance/docs/protocol/super-tokens/guides/deploy-super-token/deploy-custom-super-token) or the [Protocol Wiki](https://github.com/superfluid-finance/protocol-monorepo/wiki/About-Custom-Super-Token).

## Test your Custom Super Token Contract

Once you created your custom logic in the Custom Super Token Contract, you can now go ahead and write tests of your Custom Super Token.

Going back to the previous example of the Pure Super Token contract, we can see that the file including the tests of `PureSuperToken` contract is `PureSuperToken.t.sol`.

This file contains a deployment of the protocol in the method `setUp` as such:

```solidity
function setUp() public {
		vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
		SuperfluidFrameworkDeployer sfDeployer = new SuperfluidFrameworkDeployer();
		sfDeployer.deployTestFramework();
		_sf = sfDeployer.getFramework();
	}
```

Then the file contains 2 tests, one of deployment and the other to check the receiver's balance

```solidity
	function testDeploy() public {
		_superTokenProxy = new PureSuperTokenProxy();
		assert(address(_superTokenProxy) != address(0));
	}

	function testSuperTokenBalance() public {
		_superTokenProxy = new PureSuperTokenProxy();
		_superTokenProxy.initialize(
			_sf.superTokenFactory,
			"TestToken",
			"TST",
			_OWNER,
			1000
		);
		ISuperToken superToken = ISuperToken(address(_superTokenProxy));
		uint balance = superToken.balanceOf(_OWNER);
		assert(balance == 1000);
	}
```

To run these tests you can run the test command from Foundry:

```bash
forge test
```

## Deployment

There are multiple ways to manage the deployment of a Custom Super Token. One of them is using the following command line by replacing the proper arguments with your requirements:

```bash
forge create --rpc-url <RPC_URL_OF_DESIRED_CHAIN> --private-key <YOUR_PRIVATE_KEY> --etherscan-api-key <YOUR_ETHERSCAN_API_KEY> --verify --via-ir src/PureSuperToken.sol:PureSuperTokenProxy
```

## Learn more about Custom Super Tokens

To learn more about Custom Super Tokens, check the following resources:

- [The Custom Super Token Wiki](https://github.com/superfluid-finance/protocol-monorepo/wiki/About-Custom-Super-Token)
- [Deploy a Custom Super Token Guide](https://docs.superfluid.finance/docs/protocol/super-tokens/guides/deploy-super-token/deploy-custom-super-token)

## Bridging with xERC20

[xERC20](https://www.xerc20.com/) is a bridge-agnostic protocol which allows token issuers to _deploy crosschain native tokens with zero slippage, perfect fungibility, and granular risk settings — all while maintaining ownership of your token contracts._.

[BridgedSuperToken.sol](src/xchain/BridgedSuperToken.sol) extends a Pure SuperToken with the xerc20 interface.
The core functions are `mint` and `burn`. They leverage the hooks `selfMint` and `selfBurn` provided by the canonical Super Token implementation.
The rest of the logic is mostly about setting and enforcing rate limits per bridge. The limits are defined as the maximum token amount a bridge can mint or burn per 24 hours (rolling time window).

### Optimism / Superchain Standard Bridge

L2's based on the OP / Superchain stack can use the native [Standard Bridge](https://docs.optimism.io/builders/app-developers/bridging/standard-bridge) for maximum security.

[OPBridgedSuperToken.sol](src/xchain/OPBridgedSuperToken.sol) allows that by implementing the required ´IOptimismMintableERC20` interface.
Its `mint()` and `burn()` match those of IXERC20, but it adds `bridge()` (address of the bridge contract), `remoteToken()` (address of the token on L1) and `supportsInterface()` (ERC165 interface detection).

### HomeERC20

Is a plain OpenZeppelin based ERC20 with ERC20Votes extension.
It's suitable for multichain token deployments which want an ERC20 representation on L1 and Super Token representations on L2s.

### Arbitrum Bridge

We need to use the [generic custom gateway](https://docs.arbitrum.io/build-decentralized-apps/token-bridging/token-bridge-erc20#the-arbitrum-generic-custom-gateway)

The L2 token needs to implement [IArbToken](https://github.com/OffchainLabs/token-bridge-contracts/blob/main/contracts/tokenbridge/arbitrum/IArbToken.sol).


