import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  LiquidityAdded,
  LiquidityRemoved,
  Swap as SwapEvent,
} from "../generated/ConstantProductAMM/ConstantProductAMM";
import { LiquidityEvent, LiquidityPosition, Swap } from "../generated/schema";

function eventId(txHash: string, logIndex: BigInt): string {
  return txHash.concat("-").concat(logIndex.toString());
}

function positionId(user: string, pair: string): string {
  return user.concat("-").concat(pair);
}

function getPosition(user: string, pair: string): LiquidityPosition {
  let id = positionId(user, pair);
  let position = LiquidityPosition.load(id);
  if (position == null) {
    position = new LiquidityPosition(id);
    position.user = changetype<Bytes>(Bytes.fromHexString(user));
    position.pair = changetype<Bytes>(Bytes.fromHexString(pair));
    position.lpBalance = BigInt.zero();
    position.lastUpdated = BigInt.zero();
  }

  return position;
}

export function handleSwap(event: SwapEvent): void {
  let swap = new Swap(eventId(event.transaction.hash.toHexString(), event.logIndex));
  swap.pair = event.address;
  swap.sender = event.params.sender;
  swap.tokenIn = event.params.tokenIn;
  swap.amountIn = event.params.amountIn;
  swap.amountOut = event.params.amountOut;
  swap.to = event.params.to;
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.transactionHash = event.transaction.hash;
  swap.save();
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let position = getPosition(event.params.provider.toHexString(), event.address.toHexString());
  position.lpBalance = position.lpBalance.plus(event.params.liquidity);
  position.lastUpdated = event.block.timestamp;
  position.save();

  saveLiquidityEvent(
    event.transaction.hash.toHexString(),
    event.logIndex,
    event.address,
    event.params.provider,
    event.params.amount0,
    event.params.amount1,
    event.params.liquidity,
    "ADD",
    event.block.timestamp,
    event.block.number,
    event.transaction.hash,
  );
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let position = getPosition(event.params.provider.toHexString(), event.address.toHexString());
  position.lpBalance = position.lpBalance.minus(event.params.liquidity);
  position.lastUpdated = event.block.timestamp;
  position.save();

  saveLiquidityEvent(
    event.transaction.hash.toHexString(),
    event.logIndex,
    event.address,
    event.params.provider,
    event.params.amount0,
    event.params.amount1,
    event.params.liquidity,
    "REMOVE",
    event.block.timestamp,
    event.block.number,
    event.transaction.hash,
  );
}

function saveLiquidityEvent(
  txHash: string,
  logIndex: BigInt,
  pair: Bytes,
  provider: Bytes,
  amount0: BigInt,
  amount1: BigInt,
  liquidity: BigInt,
  action: string,
  timestamp: BigInt,
  blockNumber: BigInt,
  transactionHash: Bytes,
): void {
  let entity = new LiquidityEvent(eventId(txHash, logIndex));
  entity.pair = pair;
  entity.provider = provider;
  entity.amount0 = amount0;
  entity.amount1 = amount1;
  entity.liquidity = liquidity;
  entity.action = action;
  entity.timestamp = timestamp;
  entity.blockNumber = blockNumber;
  entity.transactionHash = transactionHash;
  entity.save();
}
