import { useState } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import "./App.css";
import { ErrorBoundary } from "./components/ErrorBoundary";
import { NetworkGuard } from "./components/NetworkGuard";
import { Borrow } from "./pages/Borrow";
import { Governance } from "./pages/Governance";
import { Liquidity } from "./pages/Liquidity";
import { Portfolio } from "./pages/Portfolio";
import { Swap } from "./pages/Swap";
import { Vault } from "./pages/Vault";

type Page =
  | "swap"
  | "liquidity"
  | "vault"
  | "borrow"
  | "governance"
  | "portfolio";

const pages: Array<{ id: Page; label: string }> = [
  { id: "swap", label: "Swap" },
  { id: "liquidity", label: "Liquidity" },
  { id: "vault", label: "Vault" },
  { id: "borrow", label: "Borrow" },
  { id: "governance", label: "Governance" },
  { id: "portfolio", label: "Portfolio" },
];

function App() {
  const [page, setPage] = useState<Page>("swap");

  return (
    <ErrorBoundary>
      <div className="app-shell">
        <header className="topbar">
          <div>
            <p className="eyebrow">Arbitrum Sepolia</p>
            <h1>DeFi Super App</h1>
          </div>
          <ConnectButton />
        </header>

        <NetworkGuard />

        <nav className="tabs" aria-label="Primary">
          {pages.map((item) => (
            <button
              key={item.id}
              className={page === item.id ? "tab active" : "tab"}
              onClick={() => setPage(item.id)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </nav>

        <main>
          {page === "swap" && <Swap />}
          {page === "liquidity" && <Liquidity />}
          {page === "vault" && <Vault />}
          {page === "borrow" && <Borrow />}
          {page === "governance" && <Governance />}
          {page === "portfolio" && <Portfolio />}
        </main>
      </div>
    </ErrorBoundary>
  );
}

export default App;
