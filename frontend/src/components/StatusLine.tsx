import { txLabel } from "../utils/format";

type Props = {
  error?: string;
  hash?: string;
};

export function StatusLine({ error, hash }: Props) {
  if (error) {
    return <p className="status error">{error}</p>;
  }
  if (hash) {
    return <p className="status success">Submitted {txLabel(hash)}</p>;
  }
  return null;
}
