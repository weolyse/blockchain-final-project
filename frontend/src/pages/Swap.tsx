import { useMemo, useState } from "react";
import { Address } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ammAbi, contracts, erc20Abi } from "../config/contracts";
import { pretty, readableError, toAmount } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

const tokenOptions = [
  { label: "DGV", address: contracts.govToken },
  { label: "DUT", address: contracts.utilityToken },
] as const;

export function Swap() {
  const { address } = useAccount();
  const [tokenIn, setTokenIn] = useState<Address>(contracts.govToken);
  const [amount, setAmount] = useState("");
  const [error, setError] = useState("");
  const { writeContractAsync, data: hash, isPending } = useWriteContract();

  const amountIn = useMemo(() => toAmount(amount), [amount]);
  const { data: quotedOut } = useReadContract({
    address: contracts.ammPair,
    abi: ammAbi,
    functionName: "getAmountOut",
    args: [tokenIn, amountIn],
    query: { enabled: amountIn > BigInt(0) },
  });

  const handleApprove = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: tokenIn,
        abi: erc20Abi,
        functionName: "approve",
        args: [contracts.ammPair, amountIn],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const handleSwap = async () => {
    if (!address) {
      setError("Connect wallet");
      return;
    }
    setError("");
    try {
      const minOut = quotedOut
        ? (quotedOut * BigInt(995)) / BigInt(1000)
        : BigInt(0);
      await writeContractAsync({
        address: contracts.ammPair,
        abi: ammAbi,
        functionName: "swap",
        args: [tokenIn, amountIn, minOut, address],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Swap</h2>
        <p className="metric">Quote {pretty(quotedOut)}</p>
      </div>
      <div className="form-grid">
        <label>
          Token
          <select
            value={tokenIn}
            onChange={(event) => setTokenIn(event.target.value as Address)}
          >
            {tokenOptions.map((token) => (
              <option key={token.address} value={token.address}>
                {token.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Amount
          <input
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            inputMode="decimal"
          />
        </label>
      </div>
      <div className="actions">
        <button
          type="button"
          onClick={handleApprove}
          disabled={isPending || amountIn === BigInt(0)}
        >
          Approve
        </button>
        <button
          type="button"
          onClick={handleSwap}
          disabled={isPending || amountIn === BigInt(0)}
        >
          Swap
        </button>
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
