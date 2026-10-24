// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Squeek} from "../src/Squeek.sol";

/// @dev Exercises mixed ERC-20 operations across a closed set of holders and tracks an
/// independent balance/allowance model. No balance or storage cheatcodes mutate the token.
contract SqueekHandler is Test {
    Squeek public immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Squeek token_, address initialHolder) {
        token = token_;
        actors[0] = initialHolder;
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        expectedBalance[initialHolder] = 1_000_000_000 * 1e18;
    }

    function actor(uint256 index) public view returns (address) {
        return actors[index % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        expectedAllowance[owner][spender] = amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        address to = actor(toSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, approved < available ? approved : available);
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actor(fromSeed);
        uint256 balance = expectedBalance[from];
        vm.prank(from);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transfer, (actor(toSeed), balance + 1)));
        _assertRejected(
            success,
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, actor(toSeed), approved + 1)));
        _assertRejected(
            success,
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
    }

    /// @dev Regular random approvals almost never select exactly zero or max-1.
    function approveAtBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 edgeSeed) external {
        uint256[6] memory edges =
            [uint256(0), 1, 1_000_000_000e18, 1_000_000_000e18 + 1, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, edges[edgeSeed % edges.length]);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        transfer(fromSeed, toSeed, expectedBalance[actor(fromSeed)]);
    }

    /// @dev Guarantees delegated spending is reachable without a lucky matching approval.
    function spendWithApproval(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        uint256 amount = bound(amountSeed, 0, expectedBalance[actor(ownerSeed)]);
        uint256 approved = unlimited ? type(uint256).max : amount;
        approve(ownerSeed, spenderSeed, approved);
        assertEq(token.allowance(actor(ownerSeed), actor(spenderSeed)), approved);
        transferFrom(ownerSeed, spenderSeed, toSeed, amount);
    }

    function rejectTransferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = actor(fromSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        _assertRejected(success, reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function rejectApproveZero(uint256 ownerSeed, uint256 amount) external {
        vm.prank(actor(ownerSeed));
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        _assertRejected(success, reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }

    function rejectTransferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, address(0), amount)));
        _assertRejected(success, reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function rejectTransferFromForBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actor(ownerSeed);
        uint256 balance = expectedBalance[owner];
        // Reach the balance failure after a finite allowance has tentatively been spent.
        approve(ownerSeed, spenderSeed, balance + 1);
        assertEq(token.allowance(owner, actor(spenderSeed)), balance + 1);
        vm.prank(actor(spenderSeed));
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, actor(toSeed), balance + 1)));
        _assertRejected(
            success,
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, balance + 1)
        );
    }

    function _assertRejected(bool success, bytes memory reason, bytes memory expected) private pure {
        assertFalse(success);
        assertEq(reason, expected);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        address initialHolder = makeAddr("invariant deployer");
        vm.prank(initialHolder);
        token = new Squeek();
        handler = new SqueekHandler(token, initialHolder);

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectOverspend.selector;
        selectors[4] = handler.rejectExcessAllowance.selector;
        selectors[5] = handler.approveAtBoundary.selector;
        selectors[6] = handler.transferFullBalance.selector;
        selectors[7] = handler.spendWithApproval.selector;
        selectors[8] = handler.rejectTransferToZero.selector;
        selectors[9] = handler.rejectApproveZero.selector;
        selectors[10] = handler.rejectTransferFromToZero.selector;
        selectors[11] = handler.rejectTransferFromForBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actor(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.allowance(handler.actor(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actor(i)), 0);
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actor(i);
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
