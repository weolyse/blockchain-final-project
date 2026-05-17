import { createConfig, http } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { arbitrumSepolia } from "./chains";

const projectId =
  process.env.REACT_APP_WALLETCONNECT_PROJECT_ID ?? "defi-super-app-local";

export const config = createConfig({
  chains: [arbitrumSepolia],
  connectors: [
    injected({ target: "metaMask" }),
    walletConnect({
      projectId,
      showQrModal: true,
      metadata: {
        name: "DeFi Super App",
        description: "AMM, lending, vault, and governance dApp",
        url: window.location.origin,
        icons: [`${window.location.origin}/logo192.png`],
      },
    }),
  ],
  transports: {
    [arbitrumSepolia.id]: http(arbitrumSepolia.rpcUrls.default.http[0]),
  },
});
