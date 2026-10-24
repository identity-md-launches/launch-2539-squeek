// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actor(fromSeed);
        address to = actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        expectedAllowance[owner][spender] = amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
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
        vm.prank(from);
        (bool success,) =
            address(token).call(abi.encodeCall(token.transfer, (actor(toSeed), expectedBalance[from] + 1)));
        assertFalse(success);
    }

    function rejectExcessAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actor(ownerSeed);
        address spender = actor(spenderSeed);
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.prank(spender);
        (bool success,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, actor(toSeed), approved + 1)));
        assertFalse(success);
    }
}

contract SqueekInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    Squeek private token;
    SqueekHandler private handler;

    function setUp() public {
        address initialHolder = makeAddr("invariant deployer");
        vm.prank(initialHolder);
        token = new Squeek();
        handler = new SqueekHandler(token, initialHolder);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.rejectOverspend.selector;
        selectors[4] = handler.rejectExcessAllowance.selector;
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
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actor(i);
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
