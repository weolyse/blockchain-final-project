# DeFi Super App

DeFi Super App is a final project implementation of a small, composable DeFi protocol on Arbitrum Sepolia. It combines a custom constant-product AMM, lending pool, ERC-4626 yield vault, Chainlink-style price adapter, Governor + Timelock governance, The Graph indexing, and a React dApp frontend.

## Architecture Overview

The system is split into four layers. Smart contracts hold all protocol state and permissions: the AMM pair handles DGV/DUT swaps and LP accounting, the lending pool tracks collateral and debt through a UUPS proxy, the vault wraps DGV deposits as ERC-4626 shares, and governance controls protocol ownership through a two-day timelock. Chainlink-compatible oracle adapters provide asset pricing for lending logic. The subgraph indexes swaps, liquidity events, vault activity, and governance events for fast frontend reads. The frontend connects wallets with Wagmi/RainbowKit, sends write transactions directly to Arbitrum Sepolia, and reads indexed governance data from The Graph.

## Repository Layout

```text
contracts/      Foundry smart contracts, deployment scripts, and tests
frontend/       React + TypeScript dApp
subgraph/       The Graph schema, mappings, and generated types
deployments/    Arbitrum Sepolia deployment and verification output
docs/           Subgraph queries and project documentation
```

## Prerequisites

- Foundry (`forge`, `cast`, `anvil`)
- Node.js 20+
- npm
- Git
- Arbitrum Sepolia RPC URL
- Arbitrum Sepolia ETH for deployment and frontend transactions
- Arbiscan API key for verification
- WalletConnect project ID for the frontend

Optional:

- Graph CLI for subgraph development
- Slither for security analysis
- `genhtml` for HTML coverage reports

## Environment

Create `.env` in the repository root:

```env
RPC_URL=https://your-arbitrum-sepolia-rpc
ARBITRUM_SEPOLIA_RPC=https://your-arbitrum-sepolia-rpc
DEPLOYER_KEY=0xyour_private_key
ARBISCAN_API_KEY=your_arbiscan_api_key
PAIR_SALT=
PRICE_FEED=
ARBITRUM_SEPOLIA_ETH_USD_FEED=
```

For Arbitrum Sepolia, `PRICE_FEED` can stay empty because the deployment script creates a mock feed on chain id `421614`.

For the frontend, create `frontend/.env` if you want to override public values:

```env
REACT_APP_ARBITRUM_SEPOLIA_RPC=https://your-arbitrum-sepolia-rpc
REACT_APP_WALLETCONNECT_PROJECT_ID=your_walletconnect_project_id
```

Load the root `.env` into PowerShell:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

## Setup

Install frontend dependencies:

```powershell
cd frontend
npm install
```

Build contracts:

```powershell
cd ..
forge build --root contracts
```

Run the frontend locally:

```powershell
cd frontend
npm start
```

Open `http://localhost:3000`, connect MetaMask, and switch to Arbitrum Sepolia when prompted.

## Testing

Run the full contract test suite:

```powershell
forge test --root contracts -vvv
```

Run coverage:

```powershell
forge coverage --root contracts --report summary
forge coverage --root contracts --report lcov
```

Run frontend checks:

```powershell
cd frontend
npx tsc --noEmit
npm run build
```

Run subgraph checks:

```powershell
cd subgraph
npm install
npx graph codegen
npx graph build
```

## Deployment

Check the deployer address:

```powershell
cast wallet address --private-key $env:DEPLOYER_KEY
```

Dry run:

```powershell
forge script contracts/script/Deploy.s.sol:Deploy `
  --rpc-url $env:RPC_URL
```

Broadcast and verify:

```powershell
forge script contracts/script/Deploy.s.sol:Deploy `
  --rpc-url $env:RPC_URL `
  --broadcast `
  --verify `
  --etherscan-api-key $env:ARBISCAN_API_KEY
```

The deployment writes addresses to `deployments/421614.json`. The script is idempotent: if that file exists, it reuses the saved deployment instead of redeploying.

Post-deployment verification:

```powershell
forge script contracts/script/Verify.s.sol:Verify `
  --rpc-url $env:RPC_URL
```

Verification output is saved in `deployments/verification-output.txt`.

## Deployed Contracts

Network: Arbitrum Sepolia (`421614`)

| Contract | Address | Arbiscan |
|---|---|---|
| GovToken | `0x399fb298082AF707711adA0b545a4F4532891556` | https://sepolia.arbiscan.io/address/0x399fb298082AF707711adA0b545a4F4532891556 |
| Utility Token | `0xfAf9d03CEe672341cE3E8a95cE11ace7f8624c8A` | https://sepolia.arbiscan.io/address/0xfAf9d03CEe672341cE3E8a95cE11ace7f8624c8A |
| AMM Factory | `0xE5164AbBf35cFa87d87232B06C638EAd76411509` | https://sepolia.arbiscan.io/address/0xE5164AbBf35cFa87d87232B06C638EAd76411509 |
| AMM Pair | `0xa1Da546c5e942DcEB2554C47b8f1FFbF68EB349E` | https://sepolia.arbiscan.io/address/0xa1Da546c5e942DcEB2554C47b8f1FFbF68EB349E |
| Lending Pool Proxy | `0xB98BA3d9bFc30b13A2aa7F751e06e9e2E054ccA0` | https://sepolia.arbiscan.io/address/0xB98BA3d9bFc30b13A2aa7F751e06e9e2E054ccA0 |
| Lending V1 Implementation | `0x0F1CA7237C9276BaE9Bf5AC34C956F248088AC89` | https://sepolia.arbiscan.io/address/0x0F1CA7237C9276BaE9Bf5AC34C956F248088AC89 |
| Yield Vault | `0xE97d8038bA22e96Ca37cCcBf70a52598f6776F6F` | https://sepolia.arbiscan.io/address/0xE97d8038bA22e96Ca37cCcBf70a52598f6776F6F |
| Position NFT | `0x6aFDF82771dCAbd933C07Beb6B9A293aD96A1cE3` | https://sepolia.arbiscan.io/address/0x6aFDF82771dCAbd933C07Beb6B9A293aD96A1cE3 |
| Price Feed | `0xf01329274321Ab337545Fa181edD39897badDC48` | https://sepolia.arbiscan.io/address/0xf01329274321Ab337545Fa181edD39897badDC48 |
| Price Feed Adapter | `0x282f689d828A15386F5fA2c80556858A18e90FeC` | https://sepolia.arbiscan.io/address/0x282f689d828A15386F5fA2c80556858A18e90FeC |
| Governor | `0x6838ce5AAb674eDfcFD4b74E8afaF5744dF5768F` | https://sepolia.arbiscan.io/address/0x6838ce5AAb674eDfcFD4b74E8afaF5744dF5768F |
| Timelock | `0xa274d612706fC4B5363Db7F9949C8Dd77e5Fa5Fc` | https://sepolia.arbiscan.io/address/0xa274d612706fC4B5363Db7F9949C8Dd77e5Fa5Fc |
| Treasury | `0x3aecc5263c9853DF849FCCcA2d7C6d97E26A6e76` | https://sepolia.arbiscan.io/address/0x3aecc5263c9853DF849FCCcA2d7C6d97E26A6e76 |

## Subgraph

Development Query URL:

```text
https://api.studio.thegraph.com/query/1753435/defi-super-app/version/latest
```

Documented example queries are in `docs/subgraph-queries.md`.

## Frontend User Flow

The dApp is a tabbed interface. Start by connecting MetaMask or WalletConnect from the top-right button. The network guard checks `chainId`; if the wallet is not on Arbitrum Sepolia, use the switch prompt before submitting transactions.

### Swap

The Swap page trades between DGV and DUT through the custom AMM pair.

1. Select the input token: DGV or DUT.
2. Enter the amount.
3. Review the quote shown in the page heading.
4. Click `Approve` to approve the AMM pair to spend the selected token.
5. After approval confirms, click `Swap`.
6. The status line shows the transaction hash or a readable error.

### Liquidity

The Liquidity page adds or removes DGV/DUT liquidity from the AMM.

1. Read the current reserve display in the page heading.
2. Enter a DGV amount and a DUT amount.
3. Click `Approve` to approve both tokens for the AMM pair.
4. Click `Add` to mint LP exposure.
5. To exit liquidity, enter an LP amount and click `Remove`.

### Vault

The Vault page interacts with the ERC-4626 yield vault.

1. Review total vault assets, your vault shares, and the previewed share amount.
2. Enter the DGV asset amount.
3. Click `Approve` so the vault can transfer your DGV.
4. Click `Deposit` to receive vault shares.
5. Click `Withdraw` with an asset amount to redeem from the vault.

### Borrow

The Borrow page interacts with the lending pool.

1. Review your health factor at the top of the page.
2. Enter a DGV amount.
3. Click `Approve` before supplying or repaying.
4. Click `Supply` to deposit DGV collateral.
5. Click `Borrow` to borrow against your collateral.
6. Click `Repay` to reduce debt and improve health factor.

### Governance

The Governance page reads proposals from The Graph and submits votes to the Governor contract.

1. Wait for the proposal list to load from the subgraph.
2. Review proposal state, end block, and vote totals.
3. Click `For`, `Against`, or `Abstain`.
4. Confirm the transaction in your wallet.

Voting power comes from DGV delegation, so use the Portfolio page first if your voting power is zero.

### Portfolio

The Portfolio page summarizes user balances and governance state.

1. Connect a wallet to load DGV, DUT, vault shares, voting power, and current delegate.
2. Enter a delegate address, or leave the field empty to delegate to yourself.
3. Click `Delegate` and confirm in your wallet.
4. Return to Governance after delegation is indexed and voting power is active.

## Security And Design Notes

- AMM swaps, liquidity changes, vault operations, and lending operations use explicit approvals before token transfers.
- AMM math follows the constant-product formula with a 0.3% fee and slippage protection.
- Lending is upgradeable through UUPS, with ownership transferred to the Timelock.
- Governance uses ERC20Votes snapshots, Governor, and a two-day TimelockController delay.
- Oracle access is abstracted through an adapter so Chainlink-specific logic is separated from protocol logic.
- The frontend wraps write transactions in `try/catch` and displays readable transaction errors.

## Team Members

| Member | Ownership Areas |
|---|---|
| Abdunur Amangeldiev | Smart contracts, deployment, frontend integration |
| Kasymov Abilmansur | Testing, security cases, documentation support |
| Ayazhan Ayetova | Subgraph, UI pages, presentation support |


# Collaborators
Abdunur Amangeldiev
Kasymov Abilmansur