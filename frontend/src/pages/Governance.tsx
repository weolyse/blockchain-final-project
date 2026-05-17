import { useEffect, useState } from "react";
import { useWriteContract } from "wagmi";
import { contracts, governorAbi, SUBGRAPH_URL } from "../config/contracts";
import { pretty, readableError } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

type Proposal = {
  proposalId: string;
  description: string;
  state: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  endBlock: string;
};

const query = `
  query ActiveProposals {
    proposals(orderBy: createdAt, orderDirection: desc, first: 10) {
      proposalId
      description
      state
      forVotes
      againstVotes
      abstainVotes
      endBlock
    }
  }
`;

export function Governance() {
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [error, setError] = useState("");
  const { writeContractAsync, data: hash, isPending } = useWriteContract();

  useEffect(() => {
    let cancelled = false;
    fetch(SUBGRAPH_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query }),
    })
      .then((response) => response.json())
      .then((body) => {
        if (!cancelled) {
          setProposals(body.data?.proposals ?? []);
        }
      })
      .catch((e) => {
        if (!cancelled) {
          setError(readableError(e));
        }
      });

    return () => {
      cancelled = true;
    };
  }, []);

  const vote = async (proposalId: string, support: number) => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.governor,
        abi: governorAbi,
        functionName: "castVote",
        args: [BigInt(proposalId), support],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Governance</h2>
        <p className="metric">{proposals.length} proposals</p>
      </div>
      <div className="proposal-list">
        {proposals.length === 0 && (
          <p className="muted">No proposals indexed yet.</p>
        )}
        {proposals.map((proposal) => (
          <article className="proposal" key={proposal.proposalId}>
            <div>
              <span className="badge">{proposal.state}</span>
              <h3>{proposal.description || proposal.proposalId}</h3>
              <p className="muted">End block {proposal.endBlock}</p>
              <p className="vote-line">
                For {pretty(BigInt(proposal.forVotes))} / Against{" "}
                {pretty(BigInt(proposal.againstVotes))} / Abstain{" "}
                {pretty(BigInt(proposal.abstainVotes))}
              </p>
            </div>
            <div className="vote-actions">
              <button
                type="button"
                onClick={() => vote(proposal.proposalId, 1)}
                disabled={isPending}
              >
                For
              </button>
              <button
                type="button"
                onClick={() => vote(proposal.proposalId, 0)}
                disabled={isPending}
              >
                Against
              </button>
              <button
                type="button"
                onClick={() => vote(proposal.proposalId, 2)}
                disabled={isPending}
              >
                Abstain
              </button>
            </div>
          </article>
        ))}
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
