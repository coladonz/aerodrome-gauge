// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/AeroGauge.sol";

contract AeroGaugeTest is Test {
    IERC20 public constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    IERC20 public constant WETH = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 public constant AERO = IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);
    IPool public constant USDC_AERO = IPool(0x6cDcb1C4A4D1C3C6d054b27AC5B77e89eAFb971d);
    IPool public constant WETH_AERO = IPool(0x7f670f78B17dEC44d5Ef68a48740b6f8849cc2e6);
    IPool public constant WETH_USDC = IPool(0xcDAC0d6c6C59727a65F871236188350531885C43);
    IGauge public constant WETH_USDC_GAUGE =
        IGauge(0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025);

    AeroGauge public gaugeM;
    address public user = address(0x1);
    address public rewardToken = address(0x2);

    function setUp() public {
        vm.createSelectFork("http://127.0.0.1:8545");

        gaugeM = new AeroGauge();

        deal(address(AERO), address(this), 1_000_000e18);
    }

    function test_deposit_zap_aero_to_weth_usdc_lp_and_deposit_into_gauge() public {
        uint beforeBal = AERO.balanceOf(address(this));
        uint depositAmount = 100e18;
        AERO.approve(address(gaugeM), depositAmount);
        gaugeM.deposit(IGauge(WETH_USDC_GAUGE), AERO, depositAmount);
        uint afterBal = AERO.balanceOf(address(this));

        assertEq(afterBal, beforeBal - depositAmount);
        assertGt(WETH_USDC_GAUGE.balanceOf(address(gaugeM)), 0);
    }

    function test_harvest_rewards_should_zap_aero_rewards_into_weth_usdc_lp_and_deposit_into_gauge()
        public
    {
        uint depositAmount = 100e18;
        AERO.approve(address(gaugeM), depositAmount);
        gaugeM.deposit(IGauge(WETH_USDC_GAUGE), AERO, depositAmount);

        vm.warp(block.timestamp + 60 * 60 * 24 * 7);

        uint beforeGaugeBal = WETH_USDC_GAUGE.balanceOf(address(gaugeM));
        gaugeM.harvest(IGauge(WETH_USDC_GAUGE));
        uint afterGaugeBal = WETH_USDC_GAUGE.balanceOf(address(gaugeM));

        assertGt(afterGaugeBal, beforeGaugeBal);
    }

    function test_withdraw_should_withdraw_lp_from_gauge() public {
        uint depositAmount = 100e18;
        AERO.approve(address(gaugeM), depositAmount);
        gaugeM.deposit(IGauge(WETH_USDC_GAUGE), AERO, depositAmount);

        vm.warp(block.timestamp + 60 * 60 * 24 * 7);
        gaugeM.harvest(IGauge(WETH_USDC_GAUGE));

        uint beforeLpBal = IERC20(address(WETH_USDC)).balanceOf(address(this));
        uint beforeGaugeBal = WETH_USDC_GAUGE.balanceOf(address(gaugeM));
        gaugeM.withdraw(IGauge(WETH_USDC_GAUGE));
        uint afterLpBal = IERC20(address(WETH_USDC)).balanceOf(address(this));
        uint afterGaugeBal = WETH_USDC_GAUGE.balanceOf(address(gaugeM));

        assertLt(afterGaugeBal, 10); // Dust amount
        assertGt(afterLpBal - beforeLpBal, beforeGaugeBal - 10);
    }
}
