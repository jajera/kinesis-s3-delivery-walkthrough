import { describe, expect, it } from "vitest";
import { validateAsides } from "../scripts/check-asides.mjs";

describe("validateAsides", () => {
  it("accepts the four allowed types", () => {
    const content = [":::tip", ":::", ":::note", ":::", ":::caution", ":::", ":::danger", ":::"];
    expect(validateAsides(content.join("\n"))).toEqual([]);
  });

  it("rejects warning and info", () => {
    const violations = validateAsides(":::warning\nx\n:::\n\n:::info\ny\n:::");
    expect(violations.map((v) => v.type)).toEqual(["warning", "info"]);
  });

  it("reports the line number", () => {
    expect(validateAsides("intro\n\n:::warning")[0].line).toBe(3);
  });

  it("ignores a closing fence", () => {
    expect(validateAsides(":::tip\nbody\n:::")).toEqual([]);
  });
});
