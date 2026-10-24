// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "src/Squeek.sol";

/// @dev Regression cases complementing the deployment and ERC-20 tests in Squeek.t.sol.
/// forge-config: default.fuzz.runs = 1024
contract SqueekEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    Squeek private token;
    address private owner;
    address private holder;
    address private spender;
    address private recipient;

    function setUp() public {
        owner = makeAddr("edge owner");
        holder = makeAddr("edge holder");
        spender = makeAddr("edge spender");
        recipient = makeAddr("edge recipient");
        vm.prank(owner);
        token = new Squeek();
    }

    function test_OneMinorUnitCanBeTransferredAndSpent() public {
        vm.prank(owner);
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.balanceOf(owner), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullSupplyDelegatedTransferExhaustsApproval() public {
        vm.prank(owner);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, SUPPLY));
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(owner, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsDecremented() public {
        uint256 approved = type(uint256).max - 1;
        vm.prank(owner);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 1));
        assertEq(token.allowance(owner, spender), approved - 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(owner), SUPPLY - 1);
    }

    function test_MaximumTransferFromFailsForBalanceEvenWithInfiniteApproval() public {
        vm.prank(owner);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, type(uint256).max);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(owner, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ReplacingInfiniteApprovalWithFiniteApprovalEnforcesNewLimit() public {
        vm.startPrank(owner);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 1);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 2);
        assertEq(token.allowance(owner, spender), 1);
        assertEq(token.balanceOf(owner), SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 1));
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_RevokingInfiniteApprovalPreventsFurtherSpending() public {
        vm.prank(owner);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        vm.prank(owner);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(owner), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_SpendingAuthorityCannotBeForwardedByApprovingAnotherSpender() public {
        vm.prank(owner);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        token.approve(recipient, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, recipient, 0, 1));
        vm.prank(recipient);
        token.transferFrom(owner, recipient, 1);
        assertEq(token.allowance(owner, spender), SUPPLY);
        assertEq(token.allowance(spender, recipient), SUPPLY);
        assertEq(token.allowance(owner, recipient), 0);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_SelfTransfersStillEnforceBalanceAndRollBackApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, SUPPLY + 1)
        );
        vm.prank(owner);
        token.transfer(owner, SUPPLY + 1);

        vm.prank(owner);
        token.approve(spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, owner, SUPPLY + 1);
        assertEq(token.allowance(owner, spender), SUPPLY + 1);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), 0);
        assertEq(token.allowance(owner, address(0)), 0);
        assertEq(token.balanceOf(owner), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroStillRevertsAndPreservesApproval() public {
        vm.prank(owner);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), 0);
        assertEq(token.allowance(owner, spender), 1);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToTokenContractStoresTokensWithoutBurning() public {
        vm.prank(owner);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendingCanBeRetriedAfterFunding(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, balance + 1, SUPPLY);
        vm.prank(owner);
        token.transfer(holder, balance);
        vm.prank(holder);
        token.approve(spender, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), amount);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(owner);
        token.transfer(holder, amount - balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(owner), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_PartitionedSpendingExhaustsExactlyOneApproval(uint256 amountSeed, uint256 firstSeed) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 first = bound(firstSeed, 0, amount);
        vm.prank(owner);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, holder, first));
        assertEq(token.allowance(owner, spender), amount - first);
        assertEq(token.balanceOf(holder), first);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount - first));
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(recipient), amount - first);
        assertEq(token.balanceOf(owner), SUPPLY - amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        assertEq(token.balanceOf(recipient), amount - first);
        assertEq(token.balanceOf(owner), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalChangesAreIdempotentAndIsolated(uint256 amount, uint256 otherAmount) public {
        vm.prank(owner);
        token.approve(recipient, otherAmount);
        vm.prank(holder);
        token.approve(spender, otherAmount);
        vm.startPrank(owner);
        assertTrue(token.approve(spender, amount));
        assertTrue(token.approve(spender, amount));
        vm.stopPrank();
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.allowance(owner, recipient), otherAmount);
        assertEq(token.allowance(holder, spender), otherAmount);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroDelegatedTransferPreservesAnyApproval(uint256 approved) public {
        vm.prank(owner);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, 0));
        assertEq(token.allowance(owner, spender), approved);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferConsumesOnlyFiniteApproval(uint256 amountSeed, uint256 approved) public {
        uint256 amount = bound(amountSeed, 0, approved < SUPPLY ? approved : SUPPLY);
        vm.prank(owner);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, owner, amount));
        assertEq(token.allowance(owner, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(owner), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
