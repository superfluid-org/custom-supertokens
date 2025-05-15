// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { BridgedSuperTokenProxy, IBridgedSuperToken, IXERC20 } from "../../src/xchain/BridgedSuperToken.sol";

contract BridgedSuperTokenTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;

    address internal _owner = address(0x42);
    address internal _user = address(0x43);
    address internal _minter = address(0x44);
    IBridgedSuperToken internal _xerc20;

    function _deployToken(address owner) internal virtual {
        // deploy proxy
        BridgedSuperTokenProxy proxy = new BridgedSuperTokenProxy();
        // initialize proxy
        proxy.initialize(sf.superTokenFactory, "Test Token", "TT", owner, 1000);
        proxy.transferOwnership(owner);

        _xerc20 = IBridgedSuperToken(address(proxy));
    }

    function setUp() public virtual {
        // deploy SF framework
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        SuperfluidFrameworkDeployer deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();

        _deployToken(_owner);
    }

    // Test cases are replicated from the reference XERC20 implementation, with small adjustments

    // contract UnitMintBurn

    function testMintRevertsIfNotApprove(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.prank(_user);
        vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
        _xerc20.mint(_user, _amount);
    }

    function testBurnRevertsWhenLimitIsTooLow(uint256 _amount0, uint256 _amount1) public {
        _amount0 = bound(_amount0, 1, 1e40);
        _amount1 = bound(_amount1, 1, 1e40);
        vm.assume(_amount1 > _amount0);
        vm.prank(_owner);
        _xerc20.setLimits(_user, _amount0, 0);

        vm.startPrank(_user);
        _xerc20.mint(_user, _amount0);
        vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
        _xerc20.burn(_user, _amount1);
        vm.stopPrank();
    }

    function testMint(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max / 2);

        vm.prank(_owner);
        _xerc20.setLimits(_user, _amount, 0);
        vm.prank(_user);
        _xerc20.mint(_minter, _amount);

        assertEq(_xerc20.balanceOf(_minter), _amount);
    }

    function testBurn(uint256 _amount) public {
        _amount = bound(_amount, 1, 1e40);
        vm.startPrank(_owner);
        _xerc20.setLimits(_user, _amount, _amount);
        vm.stopPrank();

        vm.startPrank(_user);

        _xerc20.mint(_user, _amount);
        _xerc20.burn(_user, _amount);
        vm.stopPrank();

        assertEq(_xerc20.balanceOf(_user), 0);
    }

    function testBurnRevertsWithoutApproval(uint256 _amount) public {
        _amount = bound(_amount, 1, 1e40);

        vm.prank(_owner);
        _xerc20.setLimits(_owner, _amount, _amount);

        vm.startPrank(_owner);
        vm.expectRevert();
        _xerc20.burn(_user, _amount);
        vm.stopPrank();

        assertEq(_xerc20.balanceOf(_user), 0);
    }

    function testBurnReducesAllowance(uint256 _amount, uint256 _approvalAmount) public {
        _amount = bound(_amount, 1, 1e40);
        _approvalAmount = bound(_approvalAmount, _amount, 1e45);

        vm.prank(_owner);
        _xerc20.setLimits(_minter, _amount, _amount);

        vm.prank(_user);
        _xerc20.approve(_minter, _approvalAmount);

        vm.startPrank(_minter);
        _xerc20.mint(_user, _amount);
        _xerc20.burn(_user, _amount);
        vm.stopPrank();

        assertEq(_xerc20.allowance(_user, _minter), _approvalAmount - _amount);
    }

    // contract UnitCreateParams
    function testChangeLimit(uint256 _amount, address _randomAddr) public {
        _amount = bound(_amount, 0, type(uint256).max / 2);
        vm.assume(_randomAddr != address(0));
        vm.startPrank(_owner);
        _xerc20.setLimits(_randomAddr, _amount, _amount);
        vm.stopPrank();
        assertEq(_xerc20.mintingMaxLimitOf(_randomAddr), _amount);
        assertEq(_xerc20.burningMaxLimitOf(_randomAddr), _amount);
    }

    function testRevertsWithWrongCaller() public {
        vm.expectRevert('Ownable: caller is not the owner');
        _xerc20.setLimits(_minter, 1e18, 0);
    }

    function testAddingMintersAndLimits(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _amount2,
        address _user0,
        address _user1,
        address _user2
    ) public {
        _amount0 = bound(_amount0, 1, type(uint256).max / 2);
        _amount1 = bound(_amount1, 1, type(uint256).max / 2);
        _amount2 = bound(_amount2, 1, type(uint256).max / 2);

        vm.assume(_user0 != _user1 && _user1 != _user2 && _user0 != _user2);
        uint256[] memory _limits = new uint256[](3);
        address[] memory _minters = new address[](3);

        _limits[0] = _amount0;
        _limits[1] = _amount1;
        _limits[2] = _amount2;

        _minters[0] = _user0;
        _minters[1] = _user1;
        _minters[2] = _user2;

        vm.startPrank(_owner);
        for (uint256 _i = 0; _i < _minters.length; _i++) {
            _xerc20.setLimits(_minters[_i], _limits[_i], _limits[_i]);
        }
        vm.stopPrank();

        assertEq(_xerc20.mintingMaxLimitOf(_user0), _amount0);
        assertEq(_xerc20.mintingMaxLimitOf(_user1), _amount1);
        assertEq(_xerc20.mintingMaxLimitOf(_user2), _amount2);
        assertEq(_xerc20.burningMaxLimitOf(_user0), _amount0);
        assertEq(_xerc20.burningMaxLimitOf(_user1), _amount1);
        assertEq(_xerc20.burningMaxLimitOf(_user2), _amount2);
    }

    function testchangeBridgeMintingLimitEmitsEvent(uint256 _limit) public {
        _limit = bound(_limit, 0, type(uint256).max / 2);
        vm.prank(_owner);
        vm.expectEmit(true, true, true, true);
        emit IXERC20.BridgeLimitsSet(_limit, 0, _minter);
        _xerc20.setLimits(_minter, _limit, 0);
    }

    function testchangeBridgeBurningLimitEmitsEvent(uint256 _limit) public {
        _limit = bound(_limit, 0, type(uint256).max / 2);
        vm.prank(_owner);
        vm.expectEmit(true, true, true, true);
        emit IXERC20.BridgeLimitsSet(0, _limit, _minter);
        _xerc20.setLimits(_minter, 0, _limit);
    }

    function testSettingLimitsToUnapprovedUser(uint256 _amount) public {
        _amount = bound(_amount, 1, type(uint256).max / 2);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _amount, _amount);
        vm.stopPrank();

        assertEq(_xerc20.mintingMaxLimitOf(_minter), _amount);
        assertEq(_xerc20.burningMaxLimitOf(_minter), _amount);
    }

    function testUseLimitsUpdatesLimit(uint256 _limit) public {
        _limit = bound(_limit, 1e6, type(uint256).max / 2);
        vm.warp(1_683_145_698); // current timestamp at the time of testing

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _limit);
        _xerc20.burn(_minter, _limit);
        vm.stopPrank();

        assertEq(_xerc20.mintingMaxLimitOf(_minter), _limit);
        assertEq(_xerc20.mintingCurrentLimitOf(_minter), 0);
        assertEq(_xerc20.burningMaxLimitOf(_minter), _limit);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), 0);
    }

    function testCurrentLimitIsMaxLimitIfUnused(uint256 _limit) public {
        _limit = bound(_limit, 0, type(uint256).max / 2);
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.warp(_currentTimestamp + 12 hours);

        assertEq(_xerc20.mintingCurrentLimitOf(_minter), _limit);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), _limit);
    }

    function testCurrentLimitIsMaxLimitIfOver24Hours(uint256 _limit) public {
        _limit = bound(_limit, 0, type(uint256).max / 2);
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _limit);
        _xerc20.burn(_minter, _limit);
        vm.stopPrank();

        vm.warp(_currentTimestamp + 30 hours);

        assertEq(_xerc20.mintingCurrentLimitOf(_minter), _limit);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), _limit);
    }

    function testLimitVestsLinearly(uint256 _limit) public {
        _limit = bound(_limit, 1e6, type(uint256).max / 2);
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _limit);
        _xerc20.burn(_minter, _limit);
        vm.stopPrank();

        vm.warp(_currentTimestamp + 12 hours);

        assertApproxEqRel(_xerc20.mintingCurrentLimitOf(_minter), _limit / 2, 0.1 ether);
        assertApproxEqRel(_xerc20.burningCurrentLimitOf(_minter), _limit / 2, 0.1 ether);
    }

    function testOverflowLimitMakesItMax(uint256 _limit, uint256 _usedLimit) public {
        _limit = bound(_limit, 1e6, 100_000_000_000_000e18);
        vm.assume(_usedLimit < 1e3);
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _usedLimit);
        _xerc20.burn(_minter, _usedLimit);
        vm.stopPrank();

        vm.warp(_currentTimestamp + 20 hours);

        assertEq(_xerc20.mintingCurrentLimitOf(_minter), _limit);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), _limit);
    }

    function testchangeBridgeMintingLimitIncreaseCurrentLimitByTheDifferenceItWasChanged(
        uint256 _limit,
        uint256 _usedLimit
    ) public {
        vm.assume(_limit < 1e40);
        vm.assume(_usedLimit < 1e3);
        vm.assume(_limit > _usedLimit);
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _usedLimit);
        _xerc20.burn(_minter, _usedLimit);
        vm.stopPrank();

        vm.startPrank(_owner);
        // Adding 100k to the limit
        _xerc20.setLimits(_minter, _limit + 100_000, _limit + 100_000);
        vm.stopPrank();

        assertEq(_xerc20.mintingCurrentLimitOf(_minter), (_limit - _usedLimit) + 100_000);
    }

    function testchangeBridgeMintingLimitDecreaseCurrentLimitByTheDifferenceItWasChanged(
        uint256 _limit,
        uint256 _usedLimit
    ) public {
        uint256 _currentTimestamp = 1_683_145_698;
        vm.warp(_currentTimestamp);
        _limit = bound(_limit, 1e15, 1e40);
        _usedLimit = bound(_usedLimit, 100_000, 1e9);

        vm.startPrank(_owner);
        // Setting the limit at its original limit
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _usedLimit);
        _xerc20.burn(_minter, _usedLimit);
        vm.stopPrank();

        vm.startPrank(_owner);
        // Removing 100k to the limit
        _xerc20.setLimits(_minter, _limit - 100_000, _limit - 100_000);
        vm.stopPrank();

        assertEq(_xerc20.mintingCurrentLimitOf(_minter), (_limit - _usedLimit) - 100_000);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), (_limit - _usedLimit) - 100_000);
    }

    function testChangingUsedLimitsToZero(uint256 _limit, uint256 _amount) public {
        _limit = bound(_limit, 1, 1e40);
        vm.assume(_amount < _limit);
        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);
        vm.stopPrank();

        vm.startPrank(_minter);
        _xerc20.mint(_minter, _amount);
        _xerc20.burn(_minter, _amount);
        vm.stopPrank();

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, 0, 0);
        vm.stopPrank();

        assertEq(_xerc20.mintingMaxLimitOf(_minter), 0);
        assertEq(_xerc20.mintingCurrentLimitOf(_minter), 0);
        assertEq(_xerc20.burningMaxLimitOf(_minter), 0);
        assertEq(_xerc20.burningCurrentLimitOf(_minter), 0);
    }

    function testCannotSetLockbox(address _lockbox) public {
        vm.prank(_owner);
        vm.expectRevert();
        _xerc20.setLockbox(_lockbox);
    }

    function testRemoveBridge(uint256 _limit) public {
        _limit = bound(_limit, 1, type(uint256).max / 2);

        vm.startPrank(_owner);
        _xerc20.setLimits(_minter, _limit, _limit);

        assertEq(_xerc20.mintingMaxLimitOf(_minter), _limit);
        assertEq(_xerc20.burningMaxLimitOf(_minter), _limit);
        _xerc20.setLimits(_minter, 0, 0);
        vm.stopPrank();

        assertEq(_xerc20.mintingMaxLimitOf(_minter), 0);
        assertEq(_xerc20.burningMaxLimitOf(_minter), 0);
    }

    function testStorageLayout() public {
        BridgedSuperTokenStorageTest storageTestContract = new BridgedSuperTokenStorageTest();
        storageTestContract.validateStorageLayout();
    }
}

contract BridgedSuperTokenStorageTest is BridgedSuperTokenProxy {
    error STORAGE_LOCATION_CHANGED(string _name);

    function validateStorageLayout() public pure {
        uint256 slot;
        uint256 offset;

        // storage slots 0-31: reserved for SuperToken logic via CustomSuperTokenBase
        // storage slot 32: Ownable | address _owner

        assembly { slot := bridges.slot offset := bridges.offset }
        if (slot != 33 || offset != 0) revert STORAGE_LOCATION_CHANGED("bridges");
    }
}