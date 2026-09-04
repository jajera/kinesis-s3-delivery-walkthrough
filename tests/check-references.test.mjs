import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  extractUrls,
  hasReferencesSection,
  isAwsUrl,
  loadSourceLock,
  needsReferences,
  parseFrontmatter,
} from "../scripts/check-references.mjs";

const ROOT = path.resolve(import.meta.dirname, "..");

describe("extractUrls", () => {
  it("finds markdown and bare links", () => {
    const urls = extractUrls("[docs](https://aws.amazon.com/a) and https://aws.amazon.com/b.");
    expect(urls).toContain("https://aws.amazon.com/a");
    expect(urls).toContain("https://aws.amazon.com/b");
  });
});

describe("isAwsUrl", () => {
  it("matches AWS hosts only", () => {
    expect(isAwsUrl("https://docs.aws.amazon.com/streams/")).toBe(true);
    expect(isAwsUrl("https://github.com/aws-samples/amazon-kinesis-replay")).toBe(false);
    expect(isAwsUrl("not a url")).toBe(false);
  });
});

describe("loadSourceLock", () => {
  it("reads the canonical sources from steering", () => {
    const locked = loadSourceLock(ROOT);
    expect(locked).not.toBeNull();
    expect(locked).toContain("https://docs.aws.amazon.com/streams/latest/dev/data-delivery-s3.html");
  });
});

describe("parseFrontmatter", () => {
  it("reads simple keys", () => {
    expect(parseFrontmatter('---\ntitle: "A"\ndraft: true\n---\nbody')).toMatchObject({
      title: "A",
      draft: "true",
    });
  });

  it("returns empty for a page without frontmatter", () => {
    expect(parseFrontmatter("body")).toEqual({});
  });
});

describe("needsReferences", () => {
  it("requires citations on published cli and reference pages", () => {
    expect(needsReferences("src/content/docs/cli/produce.mdx", {})).toBe(true);
    expect(needsReferences("src/content/docs/reference/commands.mdx", {})).toBe(true);
  });

  it("exempts drafts and pages outside those sections", () => {
    expect(needsReferences("src/content/docs/cli/produce.mdx", { draft: "true" })).toBe(false);
    expect(needsReferences("src/content/docs/index.mdx", {})).toBe(false);
  });
});

describe("hasReferencesSection", () => {
  it("detects a References heading at any depth", () => {
    expect(hasReferencesSection("## References\n\n- link")).toBe(true);
    expect(hasReferencesSection("### References\n")).toBe(true);
    expect(hasReferencesSection("see the references below")).toBe(false);
  });
});
