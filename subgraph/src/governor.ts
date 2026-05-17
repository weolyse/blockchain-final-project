import { BigInt } from "@graphprotocol/graph-ts";
import {
  ProposalCanceled,
  ProposalCreated,
  ProposalExecuted,
  VoteCast,
} from "../generated/DeFiGovernor/DeFiGovernor";
import { Proposal, Vote } from "../generated/schema";

function proposalEntityId(proposalId: BigInt): string {
  return proposalId.toString();
}

function voteEntityId(proposalId: BigInt, voter: string, txHash: string, logIndex: BigInt): string {
  return proposalId.toString().concat("-").concat(voter).concat("-").concat(txHash).concat("-").concat(logIndex.toString());
}

export function handleProposalCreated(event: ProposalCreated): void {
  let proposal = new Proposal(proposalEntityId(event.params.proposalId));
  proposal.proposalId = event.params.proposalId;
  proposal.proposer = event.params.proposer;
  proposal.description = event.params.description;
  proposal.state = "Active";
  proposal.forVotes = BigInt.zero();
  proposal.againstVotes = BigInt.zero();
  proposal.abstainVotes = BigInt.zero();
  proposal.startBlock = event.params.voteStart;
  proposal.endBlock = event.params.voteEnd;
  proposal.createdAt = event.block.timestamp;
  proposal.save();
}

export function handleVoteCast(event: VoteCast): void {
  let id = proposalEntityId(event.params.proposalId);
  let proposal = Proposal.load(id);
  if (proposal == null) {
    return;
  }

  if (event.params.support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(event.params.weight);
  } else if (event.params.support == 1) {
    proposal.forVotes = proposal.forVotes.plus(event.params.weight);
  } else {
    proposal.abstainVotes = proposal.abstainVotes.plus(event.params.weight);
  }
  proposal.save();

  let vote = new Vote(
    voteEntityId(
      event.params.proposalId,
      event.params.voter.toHexString(),
      event.transaction.hash.toHexString(),
      event.logIndex,
    ),
  );
  vote.proposal = id;
  vote.voter = event.params.voter;
  vote.support = event.params.support;
  vote.weight = event.params.weight;
  vote.reason = event.params.reason;
  vote.timestamp = event.block.timestamp;
  vote.blockNumber = event.block.number;
  vote.transactionHash = event.transaction.hash;
  vote.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = Proposal.load(proposalEntityId(event.params.proposalId));
  if (proposal == null) {
    return;
  }

  proposal.state = "Executed";
  proposal.executedAt = event.block.timestamp;
  proposal.save();
}

export function handleProposalCanceled(event: ProposalCanceled): void {
  let proposal = Proposal.load(proposalEntityId(event.params.proposalId));
  if (proposal == null) {
    return;
  }

  proposal.state = "Canceled";
  proposal.save();
}
