import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { arbitrumSepolia } from "../config/chains";

export function NetworkGuard() {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected || chainId === arbitrumSepolia.id) {
    return null;
  }

  return (
    <section className="network-banner">
      <span>Wrong network</span>
      <button
        type="button"
        onClick={() => switchChain({ chainId: arbitrumSepolia.id })}
        disabled={isPending}
      >
        Switch
      </button>
    </section>
  );
}
