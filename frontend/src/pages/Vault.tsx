import { useMemo, useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { contracts, erc20Abi, vaultAbi } from "../config/contracts";
import { pretty, readableError, toAmount } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

export function Vault() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const [error, setError] = useState("");
  const { writeContractAsync, data: hash, isPending } = useWriteContract();
  const assets = useMemo(() => toAmount(amount), [amount]);
  const { data: shares } = useReadContract({
    address: contracts.yieldVault,
    abi: vaultAbi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });
  const { data: totalAssets } = useReadContract({
    address: contracts.yieldVault,
    abi: vaultAbi,
    functionName: "totalAssets",
  });
  const { data: previewShares } = useReadContract({
    address: contracts.yieldVault,
    abi: vaultAbi,
    functionName: "previewDeposit",
    args: [assets],
    query: { enabled: assets > BigInt(0) },
  });

  const approve = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.govToken,
        abi: erc20Abi,
        functionName: "approve",
        args: [contracts.yieldVault, assets],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const deposit = async () => {
    if (!address) {
      setError("Connect wallet");
      return;
    }
    setError("");
    try {
      await writeContractAsync({
        address: contracts.yieldVault,
        abi: vaultAbi,
        functionName: "deposit",
        args: [assets, address],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const withdraw = async () => {
    if (!address) {
      setError("Connect wallet");
      return;
    }
    setError("");
    try {
      await writeContractAsync({
        address: contracts.yieldVault,
        abi: vaultAbi,
        functionName: "withdraw",
        args: [assets, address, address],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Vault</h2>
        <div className="metric-row">
          <span>Total {pretty(totalAssets)}</span>
          <span>Shares {pretty(shares)}</span>
          <span>Preview {pretty(previewShares)}</span>
          <span>APY 0.00%</span>
        </div>
      </div>
      <label>
        Assets
        <input
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          inputMode="decimal"
        />
      </label>
      <div className="actions">
        <button
          type="button"
          onClick={approve}
          disabled={isPending || assets === BigInt(0)}
        >
          Approve
        </button>
        <button
          type="button"
          onClick={deposit}
          disabled={isPending || assets === BigInt(0)}
        >
          Deposit
        </button>
        <button
          type="button"
          onClick={withdraw}
          disabled={isPending || assets === BigInt(0)}
        >
          Withdraw
        </button>
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
