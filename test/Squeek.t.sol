// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev Demonstrates that CREATE and CREATE2 assign the supply to the factory itself.
contract SqueekFactoryFixture {
    function deploy() external returns (Squeek) {
        return new Squeek();
    }

    function deployDeterministic(bytes32 salt) external returns (Squeek) {
        return new Squeek{salt: salt}();
    }
}

/// @dev An ERC-20 transfer must not invoke any receiver callback.
contract RejectingReceiverFixture {
    fallback() external {
        revert("unexpected callback");
    }
}

contract SqueekTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    Squeek private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new Squeek();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), deployer, SUPPLY);
        vm.prank(deployer);
        Squeek fresh = new Squeek();
        assertEq(fresh.balanceOf(deployer), SUPPLY);
    }

    function test_FactoryReceivesEntireSupply() public {
        SqueekFactoryFixture factory = new SqueekFactoryFixture();
        vm.prank(alice);
        Squeek fresh = factory.deploy();
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_Create2FactoryReceivesEntireSupply() public {
        SqueekFactoryFixture factory = new SqueekFactoryFixture();
        bytes32 salt = keccak256("Squeek deployment test");
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Squeek).creationCode))
                    )
                )
            )
        );
        vm.prank(alice);
        Squeek fresh = factory.deployDeterministic(salt);
        assertEq(address(fresh), expected);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 125e18);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 125e18));
        assertEq(token.balanceOf(alice), 125e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 125e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transfer(alice, 1);
    }

    function test_ZeroTransferFromEmptyAccountEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractDoesNotCallReceiver() public {
        RejectingReceiverFixture recipient = new RejectingReceiverFixture();
        vm.prank(deployer);
        assertTrue(token.transfer(address(recipient), 7e18));
        assertEq(token.balanceOf(address(recipient)), 7e18);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenTransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenZeroTransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);
    }

    function test_ApproveEmitsAndReplacesAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 50e18));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 20e18);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 20e18));
        assertEq(token.allowance(deployer, spender), 20e18);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_RevokingApprovalPreventsSpending() public {
        vm.startPrank(deployer);
        token.approve(spender, 50e18);
        token.approve(spender, 0);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenApprovingZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_ApprovalCanExceedCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 3e18));
        assertEq(token.allowance(alice, spender), 3e18);
        vm.prank(deployer);
        token.transfer(alice, 3e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 3e18));
        assertEq(token.balanceOf(bob), 3e18);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_TransferFromSpendsAllowanceAndEmits() public {
        vm.prank(deployer);
        token.approve(spender, 100e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 30e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 30e18));
        assertEq(token.allowance(deployer, spender), 70e18);
        assertEq(token.balanceOf(deployer), SUPPLY - 30e18);
        assertEq(token.balanceOf(alice), 30e18);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1e18));
        assertTrue(token.transferFrom(deployer, bob, 2e18));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY - 3e18);
        assertEq(token.balanceOf(alice), 1e18);
        assertEq(token.balanceOf(bob), 2e18);
    }

    function test_RevertWhenAllowanceTooSmall() public {
        vm.prank(deployer);
        token.approve(spender, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 9, 10));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 10);
        assertEq(token.allowance(deployer, spender), 9);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenUnapprovedCallerSpends() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_DeployerCannotSeizeHolderTokens() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10e18));
        assertEq(token.balanceOf(bob), 10e18);
    }

    function test_TransferFromOwnBalanceStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function test_RevertWhenTransferFromZeroSender() public {
        // Allowance validation runs before the transfer's sender validation.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_FailedTransferFromToZeroRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 7);
        assertEq(token.allowance(deployer, spender), 7);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FailedTransferFromForBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 7));
        vm.prank(spender);
        token.transferFrom(alice, bob, 7);
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 40));
        assertEq(token.allowance(deployer, spender), 60);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ZeroTransferFromWithoutApprovalEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("setMinter(address)", bob);
        vm.prank(deployer);
        token.transfer(alice, 10e18);

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool privilegedSuccess,) = address(token).call(calls[i]);
            assertFalse(privilegedSuccess);
            vm.prank(bob);
            (bool outsiderSuccess,) = address(token).call(calls[i]);
            assertFalse(outsiderSuccess);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 10e18);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10e18));
        assertEq(token.balanceOf(bob), 10e18);
    }

    function test_LaunchDistributionClaimsAndPoolTransfersAreExact() public {
        SqueekFactoryFixture factory = new SqueekFactoryFixture();
        Squeek fresh = factory.deploy();
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address remainderRecipient = makeAddr("remainderRecipient");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;

        vm.startPrank(address(factory));
        assertTrue(fresh.transfer(distributor, swarm));
        assertTrue(fresh.transfer(poolManager, pool));
        assertTrue(fresh.transfer(remainderRecipient, SUPPLY - swarm - pool));
        vm.stopPrank();
        assertEq(fresh.balanceOf(address(factory)), 0);
        assertEq(fresh.balanceOf(distributor), swarm);
        assertEq(fresh.balanceOf(poolManager), pool);
        assertEq(fresh.balanceOf(remainderRecipient), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(fresh.transfer(alice, swarm));
        assertEq(fresh.balanceOf(distributor), 0);
        assertEq(fresh.balanceOf(alice), swarm);
        vm.prank(poolManager);
        assertTrue(fresh.transfer(bob, 10e18));
        assertEq(fresh.balanceOf(bob), 10e18);
        assertEq(fresh.balanceOf(poolManager), pool - 10e18);
        vm.prank(bob);
        assertTrue(fresh.transfer(poolManager, 10e18));
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(poolManager), pool);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(uint256 rawAmount, address recipient) public {
        vm.assume(recipient != address(0) && recipient != deployer);
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransfersRoundTrip(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromUsesOnlyItsAllowance(uint256 approved, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        uint256 remaining = approved == type(uint256).max ? approved : approved - amount;
        assertEq(token.allowance(deployer, spender), remaining);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferExceedsBalance(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferExceedsAllowance(uint256 rawApproved, uint256 rawAmount) public {
        uint256 approved = bound(rawApproved, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_SelfTransferDoesNotCreateTokens(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
