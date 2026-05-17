import { Component, ErrorInfo, ReactNode } from "react";

type Props = {
  children: ReactNode;
};

type State = {
  message: string | null;
};

export class ErrorBoundary extends Component<Props, State> {
  state: State = { message: null };

  static getDerivedStateFromError(error: Error): State {
    return { message: error.message };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error(error, info);
  }

  render() {
    if (this.state.message) {
      return (
        <main className="app-shell">
          <section className="panel">
            <h1>Something went wrong</h1>
            <p className="muted">{this.state.message}</p>
          </section>
        </main>
      );
    }

    return this.props.children;
  }
}
