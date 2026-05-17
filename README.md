# DeFi Super App

Final project scaffold for a DeFi super-app: AMM, lending pool, ERC-4626 vault, Chainlink oracle integration, governance, subgraph, and frontend.

## Status

Implementation is in progress. See `BChT2_Implementation_Plan.md` for the full checklist.

## Deploy to Arbitrum Sepolia

Create a local `.env` file in the project root and paste your values:

```env
RPC_URL=https://your-arbitrum-sepolia-rpc
ARBITRUM_SEPOLIA_RPC=https://your-arbitrum-sepolia-rpc
DEPLOYER_KEY=0xyour_private_key
ARBISCAN_API_KEY=your_arbiscan_api_key
PAIR_SALT=
PRICE_FEED=
ARBITRUM_SEPOLIA_ETH_USD_FEED=
```

For Arbitrum Sepolia, `PRICE_FEED` can stay empty because the deploy script creates a mock feed on chain id `421614`. Make sure the deployer wallet has Arbitrum Sepolia ETH before broadcasting.

Load `.env` into PowerShell:

```powershell
Get-Content .env | ForEach-Object {
  if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
    [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
  }
}
```

Check the deployer address:

```powershell
cast wallet address --private-key $env:DEPLOYER_KEY
```

Run a dry deployment first:

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

The deployment writes addresses to `deployments/421614.json`. The deploy script is idempotent: if that file already exists, it skips redeployment. Delete it only when intentionally redeploying from scratch.

Run post-deployment verification:

```powershell
forge script contracts/script/Verify.s.sol:Verify `
  --rpc-url $env:RPC_URL
```

The verification script writes `deployments/verification-output.txt`.

# Deploy Subgraph
Development Query URL v0.0.1 - https://api.studio.thegraph.com/query/1753435/defi-super-app/version/latest

# Collaborators
Abdunur Amangeldiev
Kasymov Abilmansur
Ayazhan Ayetova
