// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../src/test/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SimpleStakingChef} from "../src/SimpleStakingChef.sol";
import {SimpleRewarderPerSec} from "../src/rewarders/SimpleRewarderPerSec.sol";
import {ISimpleStakingChef} from "../src/interfaces/ISimpleStakingChef.sol";
import {ISimpleRewarderPerSec} from "../src/interfaces/ISimpleRewarderPerSec.sol";

contract SimpleStakingTest is Test {
    SimpleStakingChef public chef;
    SimpleRewarderPerSec public rewarder;
    IERC20 public lpToken;
    IERC20 public rewardToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        // Deploy mock tokens
        lpToken = new MockERC20("LP Token", "LP");
        rewardToken = new MockERC20("Reward Token", "RWD");

        // Deploy main contracts
        chef = new SimpleStakingChef();
        chef.initialize();
        rewarder = new SimpleRewarderPerSec(
            rewardToken,
            lpToken,
            1 ether, // 1 token per second
            ISimpleStakingChef(address(chef)),
            false // not native token
        );
        rewarder.initialize();

        // Setup initial state
        chef.add(0, lpToken, ISimpleRewarderPerSec(address(rewarder)));

        // Fund accounts
        lpToken.transfer(alice, 1000 ether);
        lpToken.transfer(bob, 1000 ether);
        rewardToken.transfer(address(rewarder), 10000 ether);

        // Approve spending
        vm.startPrank(alice);
        lpToken.approve(address(chef), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        lpToken.approve(address(chef), type(uint256).max);
        vm.stopPrank();
    }

    function testPoolLength() public view {
        assertEq(chef.poolLength(), 1, "Chef should have 1 pool");
    }

    function testSet() public {
        chef.set(0, 100, ISimpleRewarderPerSec(address(rewarder)), true);
        (,,, uint256 allocPoint, ISimpleRewarderPerSec _rewarder) = chef.poolInfo(0);
        assertEq(allocPoint, 100, "Should set alloc point");
        assertEq(address(_rewarder), address(rewarder), "Should set rewarder");
    }

    function testUpdatePool() public {
        chef.updatePool(0);
        (,, uint256 lastRewardTimestamp,,) = chef.poolInfo(0);
        assertEq(lastRewardTimestamp, block.timestamp, "Should update last reward timestamp");
    }

    function testDeposit() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        chef.deposit(0, depositAmount);

        (uint256 amount,) = chef.userInfo(0, alice);
        assertEq(amount, depositAmount, "Deposit amount should match");
        assertEq(lpToken.balanceOf(address(chef)), depositAmount, "Chef should have LP tokens");
        vm.stopPrank();
    }

    function testPendingTokens() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        chef.deposit(0, depositAmount);

        uint256 startTime = block.timestamp;
        skip(1 days); // Advance time by 1 day

        (uint256 pendingVolt, address bonusTokenAddress, string memory bonusTokenSymbol, uint256 pendingBonusToken) =
            chef.pendingTokens(0, alice);

        assertEq(bonusTokenAddress, address(rewardToken), "Should have reward token as bonus token address");
        assertEq(bonusTokenSymbol, "RWD", "Should have reward token symbol as bonus token symbol");
        assertEq(pendingVolt, 0, "Should have no pending volt tokens");
        assertEq(
            pendingBonusToken,
            (block.timestamp - startTime) * 1 ether,
            "Should have correct amount of pending bonus tokens"
        );
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        chef.deposit(0, depositAmount);

        skip(1 days); // Advance time by 1 day

        uint256 initialBalance = lpToken.balanceOf(alice);
        chef.withdraw(0, depositAmount);

        assertEq(lpToken.balanceOf(alice), initialBalance + depositAmount, "Should receive LP tokens back");
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        chef.deposit(0, depositAmount);

        uint256 initialBalance = lpToken.balanceOf(alice);
        chef.emergencyWithdraw(0);

        assertEq(lpToken.balanceOf(alice), initialBalance + depositAmount, "Should receive LP tokens back");
        vm.stopPrank();
    }

    function testRewarderDistribution() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        chef.deposit(0, depositAmount);

        skip(1 days); // Advance time by 1 day

        uint256 initialRewardBalance = rewardToken.balanceOf(alice);
        chef.withdraw(0, depositAmount);

        assertTrue(rewardToken.balanceOf(alice) > initialRewardBalance, "Should receive reward tokens");
        vm.stopPrank();
    }

    function testSetRewardRate() public {
        assertEq(rewarder.tokenPerSec(), 1 ether, "Should have initial reward rate");
        rewarder.setRewardRate(0);
        assertEq(rewarder.tokenPerSec(), 0, "Should set reward rate");
    }

    function testRewardEmergencyWithdraw() public {
        assertEq(rewarder.balance(), 10000 ether, "Should have reward tokens");
        rewarder.emergencyWithdraw();
        assertEq(rewarder.balance(), 0, "Should have no reward tokens");
        assertEq(rewardToken.balanceOf(address(this)), 10000 ether, "Should have reward tokens");
    }
}
