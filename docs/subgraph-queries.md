# Subgraph Queries

## Q1: Recent Swaps On A Pair

```graphql
query RecentSwaps($pair: Bytes!, $limit: Int!) {
  swaps(where: { pair: $pair }, orderBy: timestamp, orderDirection: desc, first: $limit) {
    id
    amountIn
    amountOut
    sender
    tokenIn
    timestamp
  }
}
```

## Q2: Active Governance Proposals

```graphql
query ActiveProposals {
  proposals(where: { state: "Active" }, orderBy: endBlock, orderDirection: asc) {
    proposalId
    description
    forVotes
    againstVotes
    abstainVotes
    endBlock
  }
}
```

## Q3: User Liquidity Positions

```graphql
query UserPositions($user: Bytes!) {
  liquidityPositions(where: { user: $user }) {
    pair
    lpBalance
    lastUpdated
  }
}
```

## Q4: Vault Deposit History

```graphql
query VaultHistory($depositor: Bytes!) {
  vaultDeposits(where: { depositor: $depositor }, orderBy: timestamp, orderDirection: desc) {
    assets
    shares
    timestamp
  }
}
```

## Q5: Protocol Swap Volume Since Timestamp

```graphql
query SwapVolumeSince($since: BigInt!) {
  swaps(where: { timestamp_gt: $since }) {
    tokenIn
    amountIn
    amountOut
  }
}
```
