# Aerodrome Gauge Management

## 1. Gauge Management Functionalities

### Deposits

```solidity
function deposit(address gauge, address asset, uint256 amount)
    // gauge: The address of Aerodrome gauge
    // asset: Any assets that Aerodrome AMM supports
    // amount: The amount of asset to deposit
```

Users should be able to deposit any assets that Aerodrome AMM supports.
Once users deposit, it should swap the assets into underlying tokens of staking token of gauge.
Then the swapped tokens should be deposited into pool(staking token) and it should deposit the received LP token into gauge.

### Harvest

```solidity
function harvest(address gauge)
    // gauge: The address of Aerodrome gauge
```

It should claim pending rewards from the gauge.
Then it should swap the claimed reward into underlying tokens of staking token of gauge.
Then the swapped tokens should be deposited into pool(staking token) and it should deposit the received LP token into gauge.

### Withdraw

```solidity
function withdraw(address gauge)
    // gauge: The address of Aerodrome gauge
```

It should withdraw the staking token and pending reward.

## 2. Testing

- Comprehensive testing implemented, including fuzz testing for edge cases.
- It covers all of the functions.

## 3. Code Quality and Standards

- The code is structured for maintainability and efficiency.
- It follows high-quality coding practices and is well-documented.
- NatSpec comments are included for all functions and contracts to enhance clarity.

## Test Coverage

```
Ran 8 tests for test/AeroGauge.t.sol:AeroGaugeTest
[PASS] test_deposit_lp_into_gauge_directly() (gas: 549104)
[PASS] test_deposit_zap_aero_to_weth_usdc_lp_and_deposit_into_gauge() (gas: 715773)
[PASS] test_fuzz_deposit(uint256) (runs: 259, μ: 817837, ~: 817898)
[PASS] test_fuzz_deposit_harvest(uint256,uint256) (runs: 259, μ: 1385595, ~: 1399802)
[PASS] test_fuzz_deposit_harvest_withdraw(uint256,uint256) (runs: 259, μ: 1537200, ~: 1551407)
[PASS] test_fuzz_deposit_lp(uint256) (runs: 259, μ: 556293, ~: 556354)
[PASS] test_harvest_rewards_should_zap_aero_rewards_into_weth_usdc_lp_and_deposit_into_gauge() (gas: 1290830)
[PASS] test_withdraw_should_withdraw_lp_from_gauge() (gas: 1419635)
Suite result: ok. 8 passed; 0 failed; 0 skipped; finished in 1.75s (4.79s CPU time)

Ran 1 test suite in 1.75s (1.75s CPU time): 8 tests passed, 0 failed, 0 skipped (8 total tests)

╭-------------------+-----------------+----------------+--------------+-----------------╮
| File              | % Lines         | % Statements   | % Branches   | % Funcs         |
+=======================================================================================+
| src/AeroGauge.sol | 100.00% (73/73) | 98.63% (72/73) | 50.00% (1/2) | 100.00% (12/12) |
|-------------------+-----------------+----------------+--------------+-----------------|
| Total             | 100.00% (73/73) | 98.63% (72/73) | 50.00% (1/2) | 100.00% (12/12) |
╰-------------------+-----------------+----------------+--------------+-----------------╯
```
