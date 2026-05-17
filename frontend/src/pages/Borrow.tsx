import { useMemo, useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { contracts, erc20Abi, lendingAbi } from "../config/contracts";
import { pretty, readableError, toAmount } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

export function Borrow() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const [error, setError] = useState("");
  const value = useMemo(() => toAmount(amount), [amount]);
  const { writeContractAsync, data: hash, isPending } = useWriteContract();
  const { data: healthFactor } = useReadContract({
    address: contracts.lendingPool,
    abi: lendingAbi,
    functionName: "healthFactor",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  const approve = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.govToken,
        abi: erc20Abi,
        functionName: "approve",
        args: [contracts.lendingPool, value],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const deposit = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.lendingPool,
        abi: lendingAbi,
        functionName: "deposit",
        args: [contracts.govToken, value],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const borrow = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.lendingPool,
        abi: lendingAbi,
        functionName: "borrow",
        args: [contracts.govToken, value],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const repay = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.lendingPool,
        abi: lendingAbi,
        functionName: "repay",
        args: [contracts.govToken, value],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Borrow</h2>
        <p className="metric">
          Health {healthFactor === undefined ? "0" : pretty(healthFactor)}
        </p>
      </div>
      <label>
        DGV amount
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
          disabled={isPending || value === BigInt(0)}
        >
          Approve
        </button>
        <button
          type="button"
          onClick={deposit}
          disabled={isPending || value === BigInt(0)}
        >
          Supply
        </button>
        <button
          type="button"
          onClick={borrow}
          disabled={isPending || value === BigInt(0)}
        >
          Borrow
        </button>
        <button
          type="button"
          onClick={repay}
          disabled={isPending || value === BigInt(0)}
        >
          Repay
        </button>
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
