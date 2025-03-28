// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGauge} from "@aerodrome/contracts/interfaces/IGauge.sol";
import {IPool} from "@aerodrome/contracts/interfaces/IPool.sol";
import {IRouter} from "@aerodrome/contracts/interfaces/IRouter.sol";
import {IPoolFactory} from "@aerodrome/contracts/interfaces/factories/IPoolFactory.sol";

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
    IPoolFactory public constant factory =
        IPoolFactory(0x420DD381b31aEf6683db6B902084cB0FFECe40Da);

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

    /// @dev Errors
    error ZeroAmount();
    error InvalidRoute();

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
        if (amount == 0) revert ZeroAmount();
        _claimRewards(gauge);
        asset.safeTransferFrom(msg.sender, address(this), amount);
        return _deposit(asset, gauge, amount);
    }

    /// @notice Harvest rewards from the gauge.
    /// @dev It should claim pending rewards from the gauge and zap in the rewards into the gauge.
    /// @param gauge The address of the gauge.
    function harvest(IGauge gauge) external {
        _claimRewards(gauge);
        _harvest(gauge);
    }

    /// @notice Withdraw assets from the gauge.
    /// @dev It should harvest rewards from the gauge and withdraw the staking token and pending reward.
    /// @param gauge The address of the gauge.
    function withdraw(IGauge gauge) external {
        _claimRewards(gauge);
        _withdraw(gauge);
    }

    function claimVaultRewards(IGauge gauge) external {
        _claimRewards(gauge);
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
    function _withdraw(IGauge gauge) internal returns (uint256 lpAmount, uint256 reward) {
        reward = _pendingReward(gauge, msg.sender);
        lpAmount = userInfos[msg.sender][address(gauge)].amount;

        userInfos[msg.sender][address(gauge)].amount = 0;
        gaugeInfos[address(gauge)].totalShare -= lpAmount;

        gauge.withdraw(lpAmount);

        IERC20(gauge.stakingToken()).safeTransfer(msg.sender, lpAmount);
        IERC20(gauge.rewardToken()).safeTransfer(msg.sender, reward);

        emit Withdraw(msg.sender, address(gauge), lpAmount);
    }

    /// @notice Harvest rewards from the gauge.
    /// @param gauge The address of the gauge.
    function _harvest(IGauge gauge) internal {
        uint pendingRewards = _pendingReward(gauge, msg.sender);
        if (pendingRewards == 0) return;
        userInfos[msg.sender][address(gauge)].rewardDebt += pendingRewards;
        uint rewardLiquidity = _deposit(
            IERC20(gauge.rewardToken()),
            gauge,
            pendingRewards
        );

        emit Harvest(address(gauge), rewardLiquidity);
    }

    /// @notice Deposit assets into the gauge.
    /// @param asset The address of the asset.
    /// @param gauge The address of the gauge.
    /// @param amount The amount of the asset to deposit.
    /// @return liquidity The amount of liquidity received.
    function _deposit(
        IERC20 asset,
        IGauge gauge,
        uint256 amount
    ) internal returns (uint liquidity) {
        liquidity = _zapInGauge(asset, amount, gauge);
        UserInfo storage userInfo = userInfos[msg.sender][address(gauge)];
        GaugeInfo storage gaugeInfo = gaugeInfos[address(gauge)];
        userInfo.amount += liquidity;
        userInfo.rewardDebt += (liquidity * gaugeInfo.rewardPerShare) / 1e18;
        gaugeInfo.totalShare += liquidity;

        emit Deposit(msg.sender, address(gauge), liquidity);
    }

    /// @notice Claim rewards from the gauge.
    /// @param gauge The address of the gauge.
    /// @return rewardEarned The amount of rewards earned.
    function _claimRewards(IGauge gauge) internal returns (uint256 rewardEarned) {
        IERC20 rewardToken = IERC20(gauge.rewardToken());
        uint beforeBalance = rewardToken.balanceOf(address(this));
        gauge.getReward(address(this));
        rewardEarned = rewardToken.balanceOf(address(this)) - beforeBalance;

        GaugeInfo storage gaugeInfo = gaugeInfos[address(gauge)];

        if (rewardEarned == 0) return 0;
        gaugeInfo.rewardPerShare += (rewardEarned * 1e18) / gaugeInfo.totalShare;
    }

    /// @notice Zap in the assets into the gauge.
    /// @param asset The address of the asset.
    /// @param amount The amount of the asset to zap in.
    /// @param gauge The address of the gauge.
    /// @return liquidity The amount of liquidity received.
    function _zapInGauge(
        IERC20 asset,
        uint amount,
        IGauge gauge
    ) internal returns (uint liquidity) {
        if (address(asset) == address(gauge.stakingToken())) {
            asset.forceApprove(address(gauge), amount);
            gauge.deposit(amount);
            return amount;
        }

        asset.forceApprove(address(router), amount);
        IPool pool = IPool(gauge.stakingToken());
        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

        bool stable = _hasPool(address(asset), address(token0));
        IRouter.Route[] memory routesA = new IRouter.Route[](1);
        routesA[0] = IRouter.Route(
            address(asset),
            address(token0),
            stable,
            address(factory)
        );

        stable = _hasPool(address(asset), address(token1));
        IRouter.Route[] memory routesB = new IRouter.Route[](1);
        routesB[0] = IRouter.Route(
            address(asset),
            address(token1),
            stable,
            address(factory)
        );

        IRouter.Zap memory zap = _createZapInParams(
            token0,
            token1,
            pool.stable(),
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
    }

    /// @notice Check if the pool exists.
    /// @dev Stable Pool is preferred, it should revert if the pool does not exist.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @return stable Whether the pool is stable.
    function _hasPool(address token0, address token1) internal view returns (bool) {
        address stablePool = factory.getPool(token0, token1, true);
        address volatilePool = factory.getPool(token0, token1, false);
        if (stablePool != address(0)) return true;
        if (volatilePool != address(0)) return false;
        revert InvalidRoute();
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
                stable,
                address(factory),
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
                stable,
                address(factory),
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
        GaugeInfo storage gaugeInfo = gaugeInfos[address(gauge)];
        if (gaugeInfo.totalShare == 0) return 0;
        return (userInfo.amount * gaugeInfo.rewardPerShare) / 1e18 - userInfo.rewardDebt;
    }
}
