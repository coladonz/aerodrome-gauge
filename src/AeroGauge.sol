// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "@aerodrome/contracts/interfaces/IGauge.sol";
import {IPool} from "@aerodrome/contracts/interfaces/IPool.sol";
import {IRouter} from "@aerodrome/contracts/interfaces/IRouter.sol";

/// @title AeroGauge
/// @author @coladonz
/// @notice This contract is used to manage assets in the Aerodrome gauges.
contract AeroGauge {
    using SafeERC20 for IERC20;

    /// @dev UserInfo is used to store the user's amount and reward debt.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    /// @dev GaugeInfo is used to store the gauge's reward per share and total share.
    struct GaugeInfo {
        uint256 rewardPerShare;
        uint256 totalShare;
    }

    uint256 constant MAX_BPS = 10_000;
    IRouter public constant router = IRouter(0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
    address public constant factory = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    /// @dev userInfos is a mapping from user to gauge to UserInfo.
    mapping(address user => mapping(address gauge => UserInfo)) public userInfos;
    /// @dev gaugeInfos is a mapping from gauge to GaugeInfo.
    mapping(address gauge => GaugeInfo) public gaugeInfos;

    /// @dev Event emitted when a user deposits assets into the gauge.
    event Deposit(address indexed user, address indexed gauge, uint256 amount);
    /// @dev Event emitted when a user withdraws assets from the gauge.
    event Withdraw(address indexed user, address indexed gauge, uint256 amount);
    /// @dev Event emitted when a user harvests rewards from the gauge.
    event Harvest(address indexed gauge, uint256 amount);

    /// @notice Deposit assets into the gauge.
    /// @dev It should zap in the assets into the gauge.
    /// @param gauge The address of the gauge.
    /// @param asset The address of the asset.
    /// @param amount The amount of the asset to deposit.
    /// @return liquidity The amount of liquidity received.
    function deposit(
        IGauge gauge,
        IERC20 asset,
        uint256 amount
    ) external returns (uint256 liquidity) {
        _harvest(gauge);

        asset.safeTransferFrom(msg.sender, address(this), amount);
        liquidity = _zapIn(asset, amount, gauge);

        UserInfo storage userInfo = userInfos[msg.sender][address(gauge)];
        GaugeInfo storage gaugeInfo = gaugeInfos[address(gauge)];
        userInfo.amount += liquidity;
        userInfo.rewardDebt += (liquidity * gaugeInfo.rewardPerShare) / 1e18;
        gaugeInfo.totalShare += liquidity;

        emit Deposit(msg.sender, address(gauge), liquidity);
    }

    /// @notice Harvest rewards from the gauge.
    /// @dev It should claim pending rewards from the gauge and zap in the rewards into the gauge.
    /// @param gauge The address of the gauge.
    function harvest(IGauge gauge) external {
        _harvest(gauge);
    }

    /// @notice Withdraw assets from the gauge.
    /// @dev It should harvest rewards from the gauge and withdraw the staking token and pending reward.
    /// @param gauge The address of the gauge.
    function withdraw(IGauge gauge) external {
        _harvest(gauge);
        _withdraw(gauge);
    }

    /// @notice Get the pending reward of the user.
    /// @param gauge The address of the gauge.
    /// @param user The address of the user.
    /// @return The pending reward of the user.
    function pendingReward(IGauge gauge, address user) external view returns (uint256) {
        return _pendingReward(gauge, user);
    }

    /// @notice Withdraw assets from the gauge.
    /// @param gauge The address of the gauge.
    function _withdraw(IGauge gauge) internal {
        uint256 amount = userInfos[msg.sender][address(gauge)].amount;
        userInfos[msg.sender][address(gauge)].amount = 0;
        gaugeInfos[address(gauge)].totalShare -= amount;

        uint256 reward = _pendingReward(gauge, msg.sender);
        IERC20(gauge.stakingToken()).safeTransfer(msg.sender, amount + reward);

        emit Withdraw(msg.sender, address(gauge), amount + reward);
    }

    /// @notice Harvest rewards from the gauge.
    /// @param gauge The address of the gauge.
    function _harvest(IGauge gauge) internal {
        uint rewardEarned = IGauge(gauge).rewards(address(this));
        IGauge(gauge).getReward(address(this));

        uint rewardLiquidity = _zapIn(IERC20(gauge.rewardToken()), rewardEarned, gauge);

        // Update GaugeInfo
        GaugeInfo storage gaugeInfo = gaugeInfos[address(gauge)];
        gaugeInfo.rewardPerShare += (rewardLiquidity * 1e18) / gaugeInfo.totalShare;

        emit Harvest(address(gauge), rewardLiquidity);
    }

    /// @notice Zap in the assets into the gauge.
    /// @param asset The address of the asset.
    /// @param amount The amount of the asset to zap in.
    /// @param gauge The address of the gauge.
    /// @return liquidity The amount of liquidity received.
    function _zapIn(
        IERC20 asset,
        uint amount,
        IGauge gauge
    ) internal returns (uint liquidity) {
        asset.forceApprove(address(router), amount);

        IPool pool = IPool(gauge.stakingToken());
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(address(asset), address(token0), false, factory);

        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(address(asset), address(token1), false, factory);

        IRouter.Zap memory zap = _createZapInParams(
            token0,
            token1,
            false,
            amount,
            routesA,
            routesB
        );

        liquidity = router.zapIn(
            address(asset),
            amount / 2,
            amount / 2,
            zap,
            routesA,
            routesB,
            address(this),
            true
        );

        IERC20 stakingToken = IERC20(gauge.stakingToken());
        stakingToken.forceApprove(address(gauge), liquidity);
        gauge.deposit(liquidity);
    }

    /// @notice Create zap in params.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @param stable Whether the pool is stable.
    /// @param amount The amount of the asset to zap in.
    /// @param routesA The routes for the first token.
    /// @param routesB The routes for the second token.
    /// @return The zap in params.
    function _createZapInParams(
        IERC20 token0,
        IERC20 token1,
        bool stable,
        uint256 amount,
        IRouter.Route[] memory routesA,
        IRouter.Route[] memory routesB
    ) internal view returns (IRouter.Zap memory) {
        (
            uint256 amountOutMinA,
            uint256 amountOutMinB,
            uint256 amountAMin,
            uint256 amountBMin
        ) = router.generateZapInParams(
                address(token0),
                address(token1),
                false,
                factory,
                amount / 2,
                amount / 2,
                routesA,
                routesB
            );

        uint256 slippage = (stable == true) ? 300 : 50;
        amountAMin = (amountAMin * (MAX_BPS - slippage)) / MAX_BPS;
        amountBMin = (amountBMin * (MAX_BPS - slippage)) / MAX_BPS;
        return
            IRouter.Zap(
                address(token0),
                address(token1),
                false,
                factory,
                amountOutMinA,
                amountOutMinB,
                amountAMin,
                amountBMin
            );
    }

    /// @notice Get the pending reward of the user.
    /// @param gauge The address of the gauge.
    /// @param user The address of the user.
    /// @return The pending reward of the user.
    function _pendingReward(IGauge gauge, address user) internal view returns (uint256) {
        UserInfo storage userInfo = userInfos[user][address(gauge)];
        return
            (userInfo.amount * gaugeInfos[address(gauge)].rewardPerShare) /
            1e18 -
            userInfo.rewardDebt;
    }
}
