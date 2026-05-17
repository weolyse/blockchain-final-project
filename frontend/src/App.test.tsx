import { pretty, toAmount } from "./utils/format";

test("parses decimal token amounts", () => {
  expect(toAmount("1.5")).toBe(1500000000000000000n);
});

test("formats bigint token amounts", () => {
  expect(pretty(1234567890000000000n)).toBe("1.2345");
});
