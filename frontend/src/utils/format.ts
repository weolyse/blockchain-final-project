import { formatUnits, parseUnits } from "viem";

export function toAmount(value: string): bigint {
  if (!value || Number(value) <= 0) {
    return BigInt(0);
  }

  return parseUnits(value, 18);
}

export function pretty(value: unknown, digits = 4): string {
  if (typeof value !== "bigint") {
    return "0";
  }

  const formatted = formatUnits(value, 18);
  const [whole, fraction = ""] = formatted.split(".");
  const trimmed = fraction.slice(0, digits).replace(/0+$/, "");
  return trimmed ? `${whole}.${trimmed}` : whole;
}

export function txLabel(hash: string): string {
  return `${hash.slice(0, 10)}...${hash.slice(-6)}`;
}

export function readableError(error: unknown): string {
  const maybe = error as {
    code?: number;
    shortMessage?: string;
    message?: string;
  };
  if (maybe.code === 4001) {
    return "Transaction rejected by user";
  }
  if (maybe.shortMessage) {
    return maybe.shortMessage;
  }
  if (
    maybe.message?.includes("insufficient funds") ||
    maybe.message?.includes("insufficient balance")
  ) {
    return "Insufficient balance";
  }
  return maybe.message ?? "Transaction failed";
}
