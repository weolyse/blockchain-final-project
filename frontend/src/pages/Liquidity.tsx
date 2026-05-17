import { useMemo, useState } from "react";
import { useReadContract, useWriteContract } from "wagmi";
import { ammAbi, contracts, erc20Abi } from "../config/contracts";
import { pretty, readableError, toAmount } from "../utils/format";
import { StatusLine } from "../components/StatusLine";

export function Liquidity() {
  const [amount0, setAmount0] = useState("");
  const [amount1, setAmount1] = useState("");
  const [lpAmount, setLpAmount] = useState("");
  const [error, setError] = useState("");
  const { writeContractAsync, data: hash, isPending } = useWriteContract();
  const parsed0 = useMemo(() => toAmount(amount0), [amount0]);
  const parsed1 = useMemo(() => toAmount(amount1), [amount1]);
  const parsedLp = useMemo(() => toAmount(lpAmount), [lpAmount]);
  const { data: reserves } = useReadContract({
    address: contracts.ammPair,
    abi: ammAbi,
    functionName: "getReserves",
  });

  const approve = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.govToken,
        abi: erc20Abi,
        functionName: "approve",
        args: [contracts.ammPair, parsed0],
      });
      await writeContractAsync({
        address: contracts.utilityToken,
        abi: erc20Abi,
        functionName: "approve",
        args: [contracts.ammPair, parsed1],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const addLiquidity = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.ammPair,
        abi: ammAbi,
        functionName: "addLiquidity",
        args: [parsed0, parsed1, BigInt(0)],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  const removeLiquidity = async () => {
    setError("");
    try {
      await writeContractAsync({
        address: contracts.ammPair,
        abi: ammAbi,
        functionName: "removeLiquidity",
        args: [parsedLp, BigInt(0), BigInt(0)],
      });
    } catch (e) {
      setError(readableError(e));
    }
  };

  return (
    <section className="panel">
      <div className="panel-heading">
        <h2>Liquidity</h2>
        <p className="metric">
          Reserves {pretty(reserves?.[0])} / {pretty(reserves?.[1])}
        </p>
      </div>
      <div className="form-grid">
        <label>
          DGV
          <input
            value={amount0}
            onChange={(event) => setAmount0(event.target.value)}
            inputMode="decimal"
          />
        </label>
        <label>
          DUT
          <input
            value={amount1}
            onChange={(event) => setAmount1(event.target.value)}
            inputMode="decimal"
          />
        </label>
      </div>
      <div className="actions">
        <button
          type="button"
          onClick={approve}
          disabled={isPending || parsed0 === BigInt(0) || parsed1 === BigInt(0)}
        >
          Approve
        </button>
        <button
          type="button"
          onClick={addLiquidity}
          disabled={isPending || parsed0 === BigInt(0) || parsed1 === BigInt(0)}
        >
          Add
        </button>
      </div>
      <div className="form-grid single">
        <label>
          LP amount
          <input
            value={lpAmount}
            onChange={(event) => setLpAmount(event.target.value)}
            inputMode="decimal"
          />
        </label>
      </div>
      <div className="actions">
        <button
          type="button"
          onClick={removeLiquidity}
          disabled={isPending || parsedLp === BigInt(0)}
        >
          Remove
        </button>
      </div>
      <StatusLine error={error} hash={hash} />
    </section>
  );
}
