import { useState } from "react";
import { Address } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import {
  contracts,
  erc20Abi,
  govTokenAbi,
  vaultAbi,
} from "../config/contracts";
import { pretty, readableError } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

export function Portfolio() {
  const { address } = useAccount();
  const [delegatee, setDelegatee] = useState("");
  const [error, setError] = useState("");
  const { writeContractAsync, data: hash, isPending } = useWriteContract();

  const { data: govBalance } = useReadContract({
    address: contracts.govToken,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });
  const { data: utilityBalance } = useReadContract({
    address: contracts.utilityToken,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });
  const { data: vaultShares } = useReadContract({
    address: contracts.yieldVault,
    abi: vaultAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });
  const { data: votes } = useReadContract({
    address: contracts.govToken,
    abi: govTokenAbi,
    functionName: "getVotes",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });
  const { data: currentDelegate } = useReadContract({
    address: contracts.govToken,
    abi: govTokenAbi,
    functionName: "delegates",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const delegate = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.govToken,
        abi: govTokenAbi,
        functionName: "delegate",
        args: [(delegatee || address) as Address],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Portfolio</h2>
        <p className="metric">
          {address
            ? `${address.slice(0, 6)}...${address.slice(-4)}`
            : "Disconnected"}
        </p>
      </div>
      <div className="stat-grid">
        <div>
          <span>DGV</span>
          <strong>{pretty(govBalance)}</strong>
        </div>
        <div>
          <span>DUT</span>
          <strong>{pretty(utilityBalance)}</strong>
        </div>
        <div>
          <span>Vault shares</span>
          <strong>{pretty(vaultShares)}</strong>
        </div>
        <div>
          <span>Voting power</span>
          <strong>{pretty(votes)}</strong>
        </div>
      </div>
      <label>
        Delegate
        <input
          value={delegatee}
          onChange={(event) => setDelegatee(event.target.value)}
          placeholder={address ?? ""}
        />
      </label>
      <p className="muted">
        Current delegate{" "}
        {currentDelegate ?? "0x0000000000000000000000000000000000000000"}
      </p>
      <div className="actions">
        <button
          type="button"
          onClick={delegate}
          disabled={isPending || !address}
        >
          Delegate
        </button>
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
