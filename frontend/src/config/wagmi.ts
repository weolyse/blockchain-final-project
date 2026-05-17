import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { arbitrumSepolia } from "./chains";

export const config = getDefaultConfig({
  appName: "DeFi Super App",
  projectId:
    process.env.REACT_APP_WALLETCONNECT_PROJECT_ID ?? "defi-super-app-local",
  chains: [arbitrumSepolia],
  ssr: false,
});
