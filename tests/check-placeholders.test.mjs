import { describe, expect, it } from "vitest";
import { extractFencedBlocks, scanContent } from "../scripts/check-placeholders.mjs";

const fence = (body) => ["```bash", body, "```"].join("\n");

describe("extractFencedBlocks", () => {
  it("reports the line where each block starts", () => {
    const blocks = extractFencedBlocks(`intro\n\n${fence("echo hi")}`);
    expect(blocks).toHaveLength(1);
    expect(blocks[0].startLine).toBe(3);
  });

  it("keeps prose outside fences out of scope", () => {
    expect(extractFencedBlocks("account 481923756104 is fine in prose")).toHaveLength(0);
  });
});

describe("scanContent", () => {
  it("flags a real-looking account id", () => {
    const violations = scanContent(fence("echo 481923756104"));
    expect(violations.map((v) => v.rule)).toContain("account id");
  });

  it("accepts the documentation account id", () => {
    expect(scanContent(fence("echo 123456789012"))).toEqual([]);
  });

  it("accepts a placeholder ARN", () => {
    const arn = "arn:aws:kinesis:REGION:ACCOUNT_ID:channel/kds-lab-EXAMPLE";
    expect(scanContent(fence(`aws kinesis describe-channel --channel-arn ${arn}`))).toEqual([]);
  });

  it("flags an access key id", () => {
    const violations = scanContent(fence("AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"));
    expect(violations.map((v) => v.rule)).toContain("access key id");
  });

  it("allows example.com email and rejects anything else", () => {
    expect(scanContent(fence("EMAIL=you@example.com"))).toEqual([]);
    expect(scanContent(fence("EMAIL=someone@gmail.com"))).toHaveLength(1);
  });

  it("skips a line that already carries a placeholder token", () => {
    expect(scanContent(fence("# replace ACCOUNT_ID with 481923756104"))).toEqual([]);
  });
});
