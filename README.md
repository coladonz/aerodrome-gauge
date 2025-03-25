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
