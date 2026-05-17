# BChT2 Final Project — Full Implementation Plan
> **Chosen Scenario: Option A — DeFi Super-App**  
> AMM + Lending Protocol + ERC-4626 Yield Vault + Chainlink + DAO + The Graph + L2

---

## AGENT INSTRUCTIONS

Read this document top-to-bottom before writing a single line of code. Every section must be completed in order unless marked `[PARALLEL]`. Mark each checkbox as you complete it. Never skip a section — every item in Section 3 of the spec is grounds for automatic failure if missing.

---

## PHASE 0 — REPO & TOOLCHAIN SETUP
**Goal:** Green CI, correct folder structure, toolchain pinned.

### 0.1 Repository Bootstrap
- [ ] Create a new GitHub repo named `defi-super-app` (public or shared with instructor).
- [ ] Initialize with a root `.gitignore` for Foundry + Node + macOS artifacts.
- [ ] Push an initial commit: `chore: initial repo scaffold`

### 0.2 Foundry Project
```bash
forge init contracts --no-git
cd contracts
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
forge install smartcontractkit/chainlink-brownie-contracts
forge install transmissions11/solmate          # optional, for math helpers
```
- [x] Pin all lib versions in `foundry.toml` → `[profile.default]` with explicit remappings.
- [x] Set `solc = "0.8.24"` and `optimizer = true, runs = 200` in `foundry.toml`.
- [x] Confirm `forge build` exits 0.

### 0.3 Frontend Scaffold
```bash
cd ..
npx create-react-app frontend --template typescript
cd frontend
npm install ethers@6 wagmi viem @rainbow-me/rainbowkit
npm install @tanstack/react-query
```
- [x] Confirm `npm run build` exits 0.

### 0.4 The Graph Scaffold
```bash
cd ..
mkdir subgraph && cd subgraph
npm install -g @graphprotocol/graph-cli
graph init --product hosted-service --from-contract <placeholder_address> \
  --network arbitrum-sepolia defi-super-app
```
- [x] Placeholder `subgraph.yaml` committed.

### 0.5 GitHub Actions CI
Create `.github/workflows/ci.yml`:
```yaml
name: CI
on: [push, pull_request]
jobs:
  contracts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: foundry-rs/foundry-toolchain@v1
      - run: forge build --root contracts
      - run: forge test --root contracts -vvv
      - run: forge coverage --root contracts --report lcov
      - name: Install slither
        run: pip install slither-analyzer
      - run: slither contracts/src --config-file contracts/slither.config.json
  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: cd frontend && npm ci && npm run build
      - run: cd frontend && npx prettier --check "src/**/*.{ts,tsx}"
```
- [x] `slither.config.json` created with `detectors_to_exclude` list (start empty).
- [ ] First CI push → confirm both jobs go green before writing any contract logic.

### 0.6 Pre-commit Hooks
```bash
cd contracts
echo '#!/bin/sh\nforge fmt --check\ncd ../frontend && npx prettier --check "src/**/*.{ts,tsx}"' \
  > ../.git/hooks/pre-commit
chmod +x ../.git/hooks/pre-commit
```
- [ ] Commit: `chore(ci): add pre-commit fmt hook and GitHub Actions pipeline`

---

## PHASE 1 — CORE TOKEN CONTRACTS
**Commit prefix:** `feat(tokens):`

### 1.1 Governance Token — `GovToken.sol`
**File:** `contracts/src/tokens/GovToken.sol`

Must implement:
- `ERC20Votes` + `ERC20Permit` (OpenZeppelin)
- Minting restricted via `AccessControl` — only `MINTER_ROLE`
- `MAX_SUPPLY` constant enforced in mint
- `_update` override to call both `ERC20` and `ERC20Votes`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract GovToken is ERC20Votes, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant MAX_SUPPLY = 100_000_000e18;

    constructor(address admin) ERC20("DeFiGov", "DGV") ERC20Permit("DeFiGov") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces)
        returns (uint256) { return super.nonces(owner); }
}
```
- [x] Written and compiling.

### 1.2 LP Token — `LPToken.sol`
**File:** `contracts/src/tokens/LPToken.sol`
- ERC-20, minted/burned only by `AMM_ROLE`
- Uses `AccessControl`
- [x] Written and compiling.

### 1.3 NFT Receipt — `PositionNFT.sol`
**File:** `contracts/src/tokens/PositionNFT.sol`
- ERC-721, minted by lending pool to represent borrow positions
- tokenURI returns on-chain SVG or IPFS placeholder
- `MINTER_ROLE` gated
- [x] Written and compiling.

### 1.4 Unit Tests — `test/tokens/`
- [x] `GovToken.t.sol` — mint, transfer, delegate, permit, max supply revert (≥10 tests)
- [x] `LPToken.t.sol` — mint/burn role check, transfer (≥5 tests)
- [x] `PositionNFT.t.sol` — mint, ownerOf, role revert (≥5 tests)
- [ ] Commit: `feat(tokens): ERC20Votes governance token, LP token, position NFT`

---

## PHASE 2 — AMM (DeFi PRIMITIVE)
**Commit prefix:** `feat(amm):`  
> Build from scratch. No Uniswap fork. This is graded.

### 2.1 `ConstantProductAMM.sol`
**File:** `contracts/src/amm/ConstantProductAMM.sol`

**Storage layout (document for upgrade safety):**
```
slot 0: token0 address
slot 1: token1 address
slot 2: reserve0 uint112 | reserve1 uint112 | blockTimestampLast uint32
slot 3: lpToken address
slot 4: totalFeeAccrued uint256
```

**Required functions:**
- `addLiquidity(uint256 amount0, uint256 amount1, uint256 minLp)` → mints LP tokens
- `removeLiquidity(uint256 lpAmount, uint256 min0, uint256 min1)` → burns LP, returns tokens
- `swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)` → 0.3% fee, CEI pattern
- `getAmountOut(address tokenIn, uint256 amountIn)` → view, pure math
- `_update(uint256 bal0, uint256 bal1)` → internal, updates reserves + TWAP accumulators
- `price0CumulativeLast`, `price1CumulativeLast` → TWAP oracle data

**Yul assembly requirement** — implement `getAmountOut` with an inline assembly version:
```solidity
function getAmountOutAssembly(uint256 rIn, uint256 rOut, uint256 aIn)
    public pure returns (uint256 aOut) {
    assembly {
        let aInWithFee := mul(aIn, 997)
        let numerator  := mul(aInWithFee, rOut)
        let denominator := add(mul(rIn, 1000), aInWithFee)
        aOut := div(numerator, denominator)
    }
}
```
- Include a `getAmountOutSolidity` equivalent for benchmarking.

**Security checklist for this contract:**
- [x] `nonReentrant` on `swap`, `addLiquidity`, `removeLiquidity`
- [x] `SafeERC20.safeTransferFrom` for all token movements
- [x] CEI pattern: all state writes before external calls
- [x] Slippage: revert if output < `minAmountOut`
- [x] Minimum liquidity lock (1000 wei) on first `addLiquidity`

- [x] Written and compiling.

### 2.2 `AMMFactory.sol`
**File:** `contracts/src/amm/AMMFactory.sol`
- `createPair(address token0, address token1)` using `CREATE` (standard `new`)
- `createPair2(address token0, address token1, bytes32 salt)` using `CREATE2`
- Mapping `getPair[t0][t1]` → pair address
- Emits `PairCreated(address token0, address token1, address pair, uint256 pairCount)`

- [x] Written and compiling.
- [ ] Commit: `feat(amm): constant-product AMM from scratch with factory + Yul assembly`

### 2.3 AMM Tests — `test/amm/`
- [x] `AMM.t.sol`:
  - `testAddLiquidity` — check LP minted, reserves updated
  - `testRemoveLiquidity` — check tokens returned, LP burned
  - `testSwap_zeroForOne` — check amounts, k invariant
  - `testSwap_oneForZero`
  - `testSwap_RevertSlippage` — minAmountOut too high
  - `testFeeAccrual`
  - `testMinLiquidityLock`
  - Fuzz: `testFuzz_Swap(uint96 amountIn)` — k never decreases
  - Fuzz: `testFuzz_AddRemoveLiquidity(uint96 a, uint96 b)`
  - Invariant: `invariant_kNeverDecreases` — k post-swap ≥ k pre-swap
- [x] `AMMFactory.t.sol` — CREATE vs CREATE2, pair uniqueness
- [ ] Commit: `test(amm): full unit + fuzz + invariant AMM tests`

---

## PHASE 3 — LENDING POOL
**Commit prefix:** `feat(lending):`

### 3.1 `LendingPool.sol`
**File:** `contracts/src/lending/LendingPool.sol`

Must implement (UUPS upgradeable):
- `deposit(address asset, uint256 amount)` — users supply collateral
- `borrow(address asset, uint256 amount)` — borrow against collateral
- `repay(address asset, uint256 amount)` — repay debt with interest
- `liquidate(address borrower, address collateralAsset, uint256 debtAmount)` — triggered when health factor < 1
- `healthFactor(address user)` → view, `(collateralValue * LTV) / debtValue`
- Linear interest rate: `rate = baseRate + utilizationRatio * slope`
- Uses Chainlink price feed for asset valuation
- Mints `PositionNFT` on first borrow

**UUPS Upgrade pattern:**
```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract LendingPoolV1 is UUPSUpgradeable, OwnableUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```
- [x] `LendingPoolV1.sol` written.
- [x] `LendingPoolV2.sol` — adds a new feature (e.g., flash loans stub or per-asset LTV). Must demonstrate V1→V2 upgrade path in test.

### 3.2 Lending Tests — `test/lending/`
- [x] ≥15 unit tests: deposit, borrow, repay, liquidation trigger, health factor math, interest accrual
- [x] Fuzz: `testFuzz_HealthFactor(uint96 collateral, uint96 debt)`
- [x] Upgrade test: deploy V1 proxy → upgrade to V2 → verify storage preserved
- [ ] Commit: `feat(lending): UUPS lending pool V1+V2 with upgrade path`

---

## PHASE 4 — ERC-4626 YIELD VAULT
**Commit prefix:** `feat(vault):`

### 4.1 `YieldVault.sol`
**File:** `contracts/src/vault/YieldVault.sol`
- Inherits `ERC4626` (OpenZeppelin)
- `asset()` → underlying token (e.g., USDC mock)
- `totalAssets()` → returns balance + accrued yield from lending pool strategy
- `_deposit` → forwards assets to lending pool
- `_withdraw` → pulls assets from lending pool
- Custom fee: 10 bps performance fee on yield, sent to treasury
- Must pass all ERC-4626 rounding invariants (preview* vs actual never favors user over vault)

**Rounding invariant checks to include in tests:**
```
previewDeposit(assets) <= deposit(assets) // shares received
previewMint(shares) >= mint(shares)       // assets required
previewWithdraw(assets) <= withdraw(assets) // shares burned
previewRedeem(shares) >= redeem(shares)   // assets received
```

- [x] Written and compiling.

### 4.2 Vault Tests
- [x] `YieldVault.t.sol` ≥10 unit tests
- [x] Fuzz: `testFuzz_VaultDepositWithdraw(uint96 assets)` — rounding invariants hold
- [x] Fuzz: `testFuzz_VaultInflationAttack(uint96 frontrun)` — donation attack mitigated
- [ ] Commit: `feat(vault): ERC-4626 yield vault with lending strategy`

---

## PHASE 5 — CHAINLINK ORACLE INTEGRATION
**Commit prefix:** `feat(oracle):`

### 5.1 `PriceFeedAdapter.sol`
**File:** `contracts/src/oracles/PriceFeedAdapter.sol`
```solidity
interface AggregatorV3Interface { /* ... */ }

contract PriceFeedAdapter {
    uint256 public constant STALENESS_THRESHOLD = 3600; // 1 hour

    function getPrice(address feed) external view returns (uint256 price, uint8 decimals) {
        (, int256 answer, , uint256 updatedAt,) =
            AggregatorV3Interface(feed).latestRoundData();
        require(block.timestamp - updatedAt <= STALENESS_THRESHOLD, "Stale price");
        require(answer > 0, "Invalid price");
        return (uint256(answer), AggregatorV3Interface(feed).decimals());
    }
}
```
- [x] Interface abstraction: `IOracleAdapter` separates the Chainlink-specific impl.
- [x] Written and compiling.

### 5.2 Mock Aggregator — `MockAggregator.sol`
**File:** `contracts/test/mocks/MockAggregator.sol`
- Settable price, decimals, updatedAt
- `setPrice(int256 price)` for test manipulation
- `setStaleness(uint256 ts)` for staleness tests
- [x] Written.

### 5.3 Oracle Tests
- [x] `testStalePriceReverts` — set updatedAt to now - 7200, expect revert
- [x] `testNegativePriceReverts`
- [x] Fork test: `testFork_ChainlinkETHUSD` — uses real Arbitrum Sepolia feed
- [ ] Commit: `feat(oracle): Chainlink price feed adapter + staleness check + mock`

---

## PHASE 6 — GOVERNANCE
**Commit prefix:** `feat(governor):`

### 6.1 `DeFiGovernor.sol`
**File:** `contracts/src/governance/DeFiGovernor.sol`
```solidity
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract DeFiGovernor is
    Governor, GovernorSettings, GovernorCountingSimple,
    GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl
{
    constructor(IVotes token, TimelockController timelock)
        Governor("DeFiGovernor")
        GovernorSettings(1 days, 7 days, 1e18) // delay, period, threshold (1% of supply = 1M tokens)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(4) // 4%
        GovernorTimelockControl(timelock)
    {}
    // required overrides...
}
```

### 6.2 `DeFiTimelock.sol`
**File:** `contracts/src/governance/DeFiTimelock.sol`
- `TimelockController` with 2-day min delay
- Proposer role → Governor contract
- Executor role → Governor contract
- Timelock is the owner of treasury + protocol contracts

### 6.3 Treasury
- Simple `Treasury.sol` owned by Timelock
- Holds protocol fees
- `release(address token, address to, uint256 amount)` — only callable by Timelock

### 6.4 Governance Tests
End-to-end lifecycle test (critical):
```
1. Mint tokens to voters, delegate to self
2. Advance 1 block (past voting delay)
3. Propose: changeParameter(x)
4. Advance 1 day (past voting delay)
5. Cast votes FOR
6. Advance 7 days (past voting period)
7. Queue in Timelock
8. Advance 2 days (past Timelock delay)
9. Execute
10. Assert parameter changed
```
- [x] `testGovernanceLifecycle_FullE2E` — complete flow above
- [x] `testProposalThreshold_Reverts` — insufficient voting power
- [x] `testQuorum_Defeated` — not enough votes
- [x] `testTimelockDelay_Enforced`
- [x] Fuzz: `testFuzz_VotingPower(uint96 amount)`
- [ ] Commit: `feat(governor): OZ Governor + TimelockController + full lifecycle test`

---

## PHASE 7 — SECURITY HARDENING
**Commit prefix:** `fix(security):` or `feat(security):`

### 7.1 Reentrancy Case Study
- [x] Write `contracts/test/security/ReentrancyAttack.t.sol`
  - Deploy a malicious contract that calls back into `swap()` or `withdraw()`
  - Show it succeeds WITHOUT `nonReentrant` (comment out guard temporarily)
  - Show it fails WITH `nonReentrant`
  - Commit: `fix(security): demonstrate + fix reentrancy in AMM swap`

### 7.2 Access Control Case Study
- [x] Write `contracts/test/security/AccessControlAttack.t.sol`
  - Show unauthorized mint succeeds WITHOUT role check
  - Show it reverts WITH `onlyRole(MINTER_ROLE)`
  - Commit: `fix(security): demonstrate + fix unguarded mint access control`

### 7.3 Slither Cleanup
```bash
cd contracts
slither src/ --json slither-output.json
```
- [ ] Fix ALL High findings.
- [ ] Fix ALL Medium findings.
- [ ] For each Low/Informational: add an entry to `docs/audit-report.md` with justification.
- [ ] Commit: `chore(security): resolve all Slither high/medium findings`

### 7.4 Security Invariants Checklist (verify every contract)
| Item | Checked |
|---|---|
| No `tx.origin` for auth | ☐ |
| No `transfer()`/`send()` for ETH — use `call{value:}` | ☐ |
| No `block.timestamp` as randomness | ☐ |
| All ERC-20 interactions use `SafeERC20` | ☐ |
| All external call return values checked | ☐ |
| CEI pattern or `nonReentrant` on every state-changing external fn | ☐ |
| No unguarded admin functions | ☐ |

---

## PHASE 8 — L2 DEPLOYMENT
**Commit prefix:** `feat(deploy):` or `chore(deploy):`

### 8.1 Deployment Script — `contracts/script/Deploy.s.sol`
Full ordered deployment:
```
1. Deploy GovToken(deployer)
2. Deploy LPToken(deployer)
3. Deploy PositionNFT(deployer)
4. Deploy MockAggregator (testnet only, guarded by chainId check)
5. Deploy PriceFeedAdapter
6. Deploy AMMFactory
7. factory.createPair(token0, token1, salt) → pair address
8. Deploy LendingPoolV1 implementation
9. Deploy ERC1967Proxy(lendingV1, initData) → proxy
10. Deploy YieldVault(underlying, lendingProxy)
11. Deploy DeFiTimelock(2 days, [], [], deployer)
12. Deploy DeFiGovernor(govToken, timelock)
13. Grant Timelock PROPOSER_ROLE → governor
14. Grant Timelock EXECUTOR_ROLE → governor
15. Revoke deployer's TIMELOCK_ADMIN_ROLE
16. Transfer LendingPool ownership → Timelock
17. Transfer YieldVault ownership → Timelock
18. Grant GovToken MINTER_ROLE → Timelock
19. vm.broadcast() wraps steps 1–18
20. Write deployed addresses to deployments/arbitrum-sepolia.json
```

- [x] Script is idempotent: checks `deployments/<chainId>.json` before redeploying.
- [x] Script parameterized by environment variables: `DEPLOYER_KEY`, `RPC_URL`.

### 8.2 Deploy to Arbitrum Sepolia
```bash
forge script contracts/script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $DEPLOYER_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```
- [ ] All contracts verified on Arbiscan.
- [ ] Addresses saved to `deployments/arbitrum-sepolia.json`.
- [ ] Links added to `README.md`.

### 8.3 Post-Deployment Verification Script — `contracts/script/Verify.s.sol`
Checks:
- [x] `lendingPool.owner() == timelock address`
- [x] `timelock.getMinDelay() == 2 days`
- [x] `governor.votingDelay() == 1 day`
- [x] `governor.votingPeriod() == 7 days`
- [x] `governor.quorumNumerator() == 4`
- [x] Output saved to `deployments/verification-output.txt`

### 8.4 Gas Comparison Table
Measure on both Goerli (L1 simulation) and Arbitrum Sepolia. Add to `docs/gas-report.md`:

| Operation | L1 Gas | L1 Cost (gwei) | L2 Gas | L2 Cost (gwei) | Savings |
|---|---|---|---|---|---|
| addLiquidity | | | | | |
| swap | | | | | |
| deposit (vault) | | | | | |
| borrow | | | | | |
| propose | | | | | |
| castVote | | | | | |

- [ ] Commit: `docs(gas): L1 vs L2 gas comparison table for 6 operations`

---

## PHASE 9 — THE GRAPH SUBGRAPH
**Commit prefix:** `feat(subgraph):`

### 9.1 `subgraph/schema.graphql`
Minimum 4 entities:
```graphql
type Swap @entity {
  id: ID!
  pair: Bytes!
  sender: Bytes!
  tokenIn: Bytes!
  amountIn: BigInt!
  amountOut: BigInt!
  timestamp: BigInt!
  blockNumber: BigInt!
}

type LiquidityPosition @entity {
  id: ID!       # address-pair
  user: Bytes!
  pair: Bytes!
  lpBalance: BigInt!
  lastUpdated: BigInt!
}

type Proposal @entity {
  id: ID!
  proposalId: BigInt!
  proposer: Bytes!
  description: String!
  state: String!
  forVotes: BigInt!
  againstVotes: BigInt!
  abstainVotes: BigInt!
  startBlock: BigInt!
  endBlock: BigInt!
}

type VaultDeposit @entity {
  id: ID!
  depositor: Bytes!
  assets: BigInt!
  shares: BigInt!
  timestamp: BigInt!
}
```

### 9.2 `subgraph/subgraph.yaml`
- Data sources: AMM pair, Governor, YieldVault
- Event handlers for: `Swap`, `LiquidityAdded`, `LiquidityRemoved`, `ProposalCreated`, `VoteCast`, `ProposalExecuted`, `Deposit`, `Withdraw`

### 9.3 `subgraph/src/mappings/`
- `amm.ts` — handles AMM events
- `governor.ts` — handles governance events
- `vault.ts` — handles vault events

### 9.4 Deploy Subgraph
```bash
cd subgraph
graph auth --studio <deploy-key>
graph codegen && graph build
graph deploy --studio defi-super-app
```
- [ ] Subgraph deployed and live.
- [ ] Subgraph URL added to README.

### 9.5 Document 5 GraphQL Queries in `docs/subgraph-queries.md`
```graphql
# Q1: Recent swaps on a pair
query RecentSwaps($pair: Bytes!, $limit: Int!) {
  swaps(where: { pair: $pair }, orderBy: timestamp, orderDirection: desc, first: $limit) {
    id amountIn amountOut sender timestamp
  }
}

# Q2: Active governance proposals
query ActiveProposals {
  proposals(where: { state: "Active" }) {
    proposalId description forVotes againstVotes endBlock
  }
}

# Q3: User's liquidity positions
query UserPositions($user: Bytes!) {
  liquidityPositions(where: { user: $user }) {
    pair lpBalance lastUpdated
  }
}

# Q4: Vault deposit history
query VaultHistory($depositor: Bytes!) {
  vaultDeposits(where: { depositor: $depositor }, orderBy: timestamp) {
    assets shares timestamp
  }
}

# Q5: Protocol-wide stats (total swaps 24h)
query DailySwapVolume($since: BigInt!) {
  swaps(where: { timestamp_gt: $since }) {
    amountIn tokenIn
  }
}
```
- [ ] Commit: `feat(subgraph): schema, mappings, 5 documented GraphQL queries`

---

## PHASE 10 — FRONTEND DAPP
**Commit prefix:** `feat(frontend):`

### 10.1 App Structure
```
frontend/src/
  components/
    WalletConnect.tsx     # RainbowKit ConnectButton
    NetworkGuard.tsx      # detect wrong chain → prompt switch
    ErrorBoundary.tsx     # catch TX errors, show readable message
  pages/
    Swap.tsx              # AMM swap UI
    Liquidity.tsx         # add/remove liquidity
    Vault.tsx             # deposit/withdraw ERC-4626 vault
    Borrow.tsx            # lending pool UI
    Governance.tsx        # proposals list + vote button
    Portfolio.tsx         # user balances, voting power, delegate
  hooks/
    useAMM.ts             # read reserves, swap write
    useVault.ts           # deposit/withdraw/shares balance
    useGovernor.ts        # proposals from subgraph, castVote write
    useUserState.ts       # token balance, voting power, delegate
  config/
    chains.ts             # Arbitrum Sepolia chain config
    contracts.ts          # deployed addresses + ABIs
    wagmi.ts              # RainbowKit + WagmiConfig setup
```

### 10.2 Mandatory UI Features (checklist)
- [ ] **Wallet connection** — RainbowKit with MetaMask + WalletConnect
- [ ] **Network detection** — if `chainId !== arbitrumSepolia.id`, show banner with `switchNetwork()` button
- [ ] **Token balance display** — GovToken balance, voting power, delegate address
- [ ] **AMM Swap page** — input token amount, show expected output, submit tx
- [ ] **Vault Deposit/Withdraw page** — show shares balance, APY estimate
- [ ] **Governance page** — fetch proposals FROM SUBGRAPH (not contract directly), show state badge, vote FOR/AGAINST/ABSTAIN buttons
- [ ] **Error handling** — wrap all `writeContract` calls in try/catch, display `toast` with readable message for: user rejection, wrong network, insufficient balance, contract revert with reason

### 10.3 Error Handling Pattern
```typescript
const handleSwap = async () => {
  try {
    const hash = await writeContractAsync({ ... });
    toast.success(`Swap submitted: ${hash.slice(0,10)}...`);
  } catch (e: any) {
    if (e.code === 4001) toast.error("Transaction rejected by user");
    else if (e.message?.includes("insufficient balance")) toast.error("Insufficient balance");
    else toast.error(`Transaction failed: ${e.shortMessage ?? e.message}`);
  }
};
```

- [ ] At least **3 write transactions** callable from UI: swap, vault deposit, castVote.
- [ ] At least **1 page reads from subgraph** (Governance page).
- [ ] Commit: `feat(frontend): full dApp with wallet, swap, vault, governance pages`

---

## PHASE 11 — COMPLETE TEST SUITE AUDIT
**Target: ≥80 tests, ≥90% line coverage**

### 11.1 Test Count Tracker
| Category | Target | Current |
|---|---|---|
| Unit tests | ≥50 | |
| Fuzz tests | ≥10 | |
| Invariant tests | ≥5 | |
| Fork tests | ≥3 | |
| **Total** | **≥80** | 92 |

### 11.2 Required Fuzz Tests (verify each exists)
- [x] `testFuzz_Swap(uint96 amountIn)` in `AMM.t.sol`
- [x] `testFuzz_AddRemoveLiquidity(uint96 a, uint96 b)` in `AMM.t.sol`
- [x] `testFuzz_VaultDepositWithdraw(uint96 assets)` in `YieldVault.t.sol`
- [x] `testFuzz_VaultInflationAttack(uint96 frontrun)` in `YieldVault.t.sol`
- [x] `testFuzz_HealthFactor(uint96 collateral, uint96 debt)` in `LendingPool.t.sol`
- [x] `testFuzz_VotingPower(uint96 amount)` in `Governor.t.sol`
- [x] `testFuzz_GovTokenDelegate(address delegatee)` in `GovToken.t.sol`
- [x] `testFuzz_PriceFeed(int256 price, uint256 age)` in `Oracle.t.sol`
- [x] `testFuzz_LPMint(uint96 a, uint96 b, uint96 c)` in `AMM.t.sol`
- [x] `testFuzz_RepayInterest(uint96 principal, uint256 time)` in `LendingPool.t.sol`

### 11.3 Required Invariant Tests
- [ ] `invariant_kNeverDecreases` — `reserve0 * reserve1 >= k_before` after any swap
- [ ] `invariant_totalSupplyConservation` — `GovToken.totalSupply() <= MAX_SUPPLY`
- [ ] `invariant_vaultSolvency` — `vault.totalAssets() >= vault.totalSupply() * pricePerShare`
- [ ] `invariant_treasuryAccounting` — fees collected equals sum of all fee events
- [ ] `invariant_timelockOwnsProtocol` — lending pool owner is always Timelock

### 11.4 Required Fork Tests
- [ ] `testFork_ChainlinkFeed` — call real Arbitrum Sepolia ETH/USD feed, check not stale
- [ ] `testFork_UniswapV2Router` — swap via real Uniswap V2 router on testnet
- [ ] `testFork_USDC_Transfer` — interact with real USDC contract

### 11.5 Run Coverage
```bash
forge coverage --root contracts --report summary
# Must show ≥90% line coverage across contracts/src/
forge coverage --root contracts --report lcov
genhtml lcov.info -o coverage-html
```
- [ ] Coverage report committed to `docs/coverage-report.md`.
- [ ] Commit: `test: complete test suite — 80+ tests, 90%+ coverage`

---

## PHASE 12 — DOCUMENTATION
**Commit prefix:** `docs:`

### 12.1 Architecture Document — `docs/architecture.md` (≥6 pages)
Structure:
1. **System Context Diagram (C4 Level 1)** — users, your protocol, external systems (Chainlink, The Graph, L2 bridge, MetaMask)
2. **Container/Component Diagram** — all contracts with relationships, proxy layout, role assignments
3. **Sequence Diagrams** (3 minimum):
   - Swap flow: user → frontend → AMM → reserves updated → LP fee accrued
   - Propose→Vote→Queue→Execute governance flow
   - Deposit→Borrow→Repay lending flow
4. **Storage Layouts** — every contract's storage slots in a table (critical for UUPS)
5. **Trust Assumptions** — Timelock powers, multisig powers, what breaks if admin is compromised
6. **Architecture Decision Records (ADRs)**:
   - ADR-001: Why UUPS over Transparent Proxy
   - ADR-002: Why Foundry over Hardhat
   - ADR-003: Why Arbitrum Sepolia L2
   - ADR-004: Why constant-product AMM over LMSR
   - ADR-005: Why ERC20Votes for governance token
7. **Design Patterns Used** (must list all 5+):
   - Factory pattern → AMMFactory
   - Proxy/UUPS → LendingPool
   - Checks-Effects-Interactions → all state-changing functions
   - Access Control / Role-based → AccessControl on all privileged functions
   - Timelock → 2-day governance delay
   - Reentrancy Guard → AMM, vault, lending pool
   - Oracle adapter → PriceFeedAdapter interface abstraction

### 12.2 Security Audit Report — `docs/audit-report.md` (≥8 pages)
Structure:
1. **Executive Summary** — 1 page, overall risk rating, top findings
2. **Scope** — commit hash, files in scope vs out of scope
3. **Methodology** — Slither, manual review, fuzz testing, invariant testing
4. **Findings Table**:

| ID | Title | Severity | Status |
|---|---|---|---|
| S-01 | Reentrancy in AMM.swap | High | Fixed |
| S-02 | Unguarded mint in GovToken | High | Fixed |
| S-03 | ... | ... | ... |

5. **Per-Finding Detail** (for each finding):
   - Title, Severity, Location (file:line), Description, Impact, Proof of Concept (code), Recommendation, Status

6. **Centralization Analysis** — who has what roles, what happens if compromised
7. **Governance Attack Analysis**:
   - Flash-loan attack → mitigated by ERC20Votes snapshot at proposal block
   - Whale attack → 4% quorum + 1% threshold limits spam
   - Proposal spam → proposal threshold prevents cheap spam
   - Timelock bypass → only Governor can queue; admin role revoked
8. **Oracle Attack Analysis**:
   - Price manipulation → TWAP recommended for AMM pricing
   - Stale price → STALENESS_THRESHOLD check in PriceFeedAdapter
   - Feed depeg → circuit breaker via Pausable
9. **Slither Output** (appendix)

### 12.3 Gas Report — `docs/gas-report.md`
- Before/after assembly optimization benchmarks for `getAmountOut`
- L1 vs L2 gas table (6 operations)
- Packed storage analysis for AMM reserves

### 12.4 README.md
Must contain:
- [ ] Project description
- [ ] Architecture overview (1 paragraph)
- [ ] Prerequisites (Foundry, Node 20, env vars)
- [ ] Setup & run instructions
- [ ] Test instructions with coverage command
- [ ] Deployed contract addresses (Arbitrum Sepolia) with Arbiscan links
- [ ] Subgraph URL
- [ ] Team members + ownership areas

- [ ] Commit: `docs: architecture doc, audit report, gas report, README`

---

## PHASE 13 — PRESENTATION SLIDE DECK
**Commit prefix:** `docs(slides):`

### Slide Structure (PDF, ~15 slides):
1. **Title** — Project name, team members, date
2. **Problem & Solution** — What DeFi problem this solves
3. **Architecture Overview** — High-level diagram
4. **Smart Contract Deep Dive** — AMM math, vault flow
5. **Security Highlights** — Top findings, mitigations
6. **Governance System** — Lifecycle diagram
7. **Oracle Integration** — Staleness check, mock pattern
8. **Testing Strategy** — Numbers: 80+ tests, coverage %, fuzz runs
9. **L2 Deployment** — Gas savings table
10. **The Graph Integration** — Schema, live query demo
11. **Frontend Demo** — Screenshots of each page
12. **Gas Optimization** — Assembly vs Solidity benchmark
13. **Known Limitations & Future Work**
14. **Q&A** — Architecture diagram for reference
15. **Appendix** — Contract addresses, subgraph URL

- [ ] Exported as PDF to `docs/presentation.pdf`.
- [ ] Commit: `docs(slides): final presentation deck PDF`

---

## PHASE 14 — FINAL CHECKLIST BEFORE SUBMISSION

### Smart Contracts
- [ ] All contracts compile with zero warnings
- [ ] UUPS proxy + V1→V2 upgrade demonstrated in test
- [ ] AMMFactory uses both CREATE and CREATE2
- [ ] Inline Yul assembly benchmarked vs pure Solidity
- [ ] ERC20Votes + ERC20Permit governance token
- [ ] ERC-721 position NFT
- [ ] ERC-4626 vault passes rounding invariants
- [ ] Constant-product AMM with 0.3% fee, slippage, LP tokens
- [ ] Chainlink integration with staleness check
- [ ] Subgraph with ≥4 entities, ≥5 documented queries
- [ ] Full Governor + TimelockController (2-day delay)
- [ ] All contracts deployed + verified on Arbitrum Sepolia

### Security
- [ ] `slither src/` → 0 High, 0 Medium
- [ ] All Low/Info findings documented + justified in audit report
- [ ] Reentrancy case study with before/after test
- [ ] Access control case study with before/after test
- [ ] No `tx.origin`, no `transfer()`/`send()`, no `block.timestamp` randomness

### Testing
- [ ] ≥50 unit tests
- [ ] ≥10 fuzz tests
- [ ] ≥5 invariant tests
- [ ] ≥3 fork tests
- [ ] ≥80 total tests
- [ ] ≥90% line coverage
- [ ] ALL tests pass (`forge test` exits 0)
- [ ] CI is green on final commit

### Frontend
- [ ] Wallet connect (MetaMask + WalletConnect)
- [ ] Wrong network detection + switch prompt
- [ ] Token balance, voting power, delegate address displayed
- [ ] AMM swap write transaction
- [ ] Vault deposit write transaction
- [ ] castVote write transaction
- [ ] Proposals fetched from The Graph (not from contract)
- [ ] Readable error messages for all failure modes

### DevOps
- [ ] GitHub Actions CI: compile + test + coverage + Slither on every push
- [ ] Pre-commit hook: `forge fmt --check` + Prettier
- [ ] Deploy script idempotent, parameterized, no manual steps
- [ ] Post-deployment verification script output committed
- [ ] All contract addresses verified on L2 block explorer

### Documentation
- [ ] Architecture document ≥6 pages with all required sections
- [ ] Security audit report ≥8 pages with all required sections
- [ ] Gas report with L1 vs L2 table (6 operations) + assembly benchmark
- [ ] Coverage report markdown committed
- [ ] README with all addresses, links, setup instructions
- [ ] 5 design patterns documented in architecture doc
- [ ] Subgraph queries documented

### Git Discipline
- [ ] Conventional commit messages throughout (`feat:`, `fix:`, `test:`, `docs:`)
- [ ] No "asdf", "fixed stuff", "final v2" messages
- [ ] First commit before end of Week 6
- [ ] Each team member has clearly attributed commits

---

## COMMIT SEQUENCE SUMMARY

| Phase | Example Commits |
|---|---|
| 0 | `chore: initial repo scaffold`, `chore(ci): GitHub Actions + pre-commit hook` |
| 1 | `feat(tokens): ERC20Votes gov token, LP token, position NFT` |
| 2 | `feat(amm): constant-product AMM with Yul assembly + factory` |
| 3 | `feat(lending): UUPS lending pool V1+V2` |
| 4 | `feat(vault): ERC-4626 yield vault` |
| 5 | `feat(oracle): Chainlink adapter + staleness + mock` |
| 6 | `feat(governor): OZ Governor + Timelock 2-day delay` |
| 7 | `fix(security): reentrancy + access control case studies` |
| 8 | `feat(deploy): Deploy.s.sol + Arbitrum Sepolia + verification script` |
| 9 | `feat(subgraph): schema + mappings + 5 queries` |
| 10 | `feat(frontend): full dApp` |
| 11 | `test: 80+ tests, 90% coverage, all passing` |
| 12 | `docs: architecture, audit report, gas report, README` |
| 13 | `docs(slides): final presentation PDF` |

---

## GRADING POINTS MAP

| Rubric Item (spec §9) | Points | Covered By Phases |
|---|---|---|
| Smart contract implementation | 20 | 1–6 |
| Security (Slither, access control, audit) | 15 | 7, 12 |
| Testing (coverage, fuzz, invariant, fork) | 15 | 11 |
| Code quality & design patterns | 10 | All phases + 12 |
| Frontend + subgraph | 10 | 9, 10 |
| Deployment & L2 verification | 5 | 8 |
| Documentation | 10 | 12 |
| Git discipline & contribution | 5 | All phases |
| Presentation / Q&A | 10 | 13 |
| **Total** | **100** | |

---

*End of implementation plan. Begin at Phase 0 and check each box before advancing.*
