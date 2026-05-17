import { Deposit, Withdraw } from "../generated/YieldVault/YieldVault";
import { VaultDeposit, VaultWithdraw } from "../generated/schema";

export function handleDeposit(event: Deposit): void {
  let deposit = new VaultDeposit(event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString()));
  deposit.depositor = event.params.sender;
  deposit.owner = event.params.owner;
  deposit.assets = event.params.assets;
  deposit.shares = event.params.shares;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.transactionHash = event.transaction.hash;
  deposit.save();
}

export function handleWithdraw(event: Withdraw): void {
  let withdraw = new VaultWithdraw(event.transaction.hash.toHexString().concat("-").concat(event.logIndex.toString()));
  withdraw.sender = event.params.sender;
  withdraw.receiver = event.params.receiver;
  withdraw.owner = event.params.owner;
  withdraw.assets = event.params.assets;
  withdraw.shares = event.params.shares;
  withdraw.timestamp = event.block.timestamp;
  withdraw.blockNumber = event.block.number;
  withdraw.transactionHash = event.transaction.hash;
  withdraw.save();
}
