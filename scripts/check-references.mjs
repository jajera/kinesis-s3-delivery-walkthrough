#!/usr/bin/env node
/**
 * Source-lock enforcement — the automated half of .kiro/steering/aws-source-lock.md.
 *
 * Three gates:
 *   1. Every AWS URL used in content appears in the source lock. Adding a source is a deliberate
 *      edit to the steering file, not something that drifts in mid-paragraph.
 *   2. Every published walkthrough or reference page carries a References section.
 *   3. Every AWS link resolves. Set SKIP_LINK_CHECK=1 to skip the network pass offline.
 *
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SOURCE_LOCK = ".kiro/steering/aws-source-lock.md";
const AWS_HOST = /(^|\.)(aws\.amazon\.com|amazonaws\.com|aws\.dev)$/i;

/** Sections that must show their working. */
const CITED_SECTIONS = ["cli/", "walkthrough/", "reference/"];

export function extractUrls(content) {
  const urls = new Set();
  const markdown = /\[[^\]]*\]\((https?:\/\/[^)\s]+)\)/g;
  let match;
  while ((match = markdown.exec(content)) !== null) urls.add(match[1]);
  const bare = /https?:\/\/[^\s)`"'<>\]]+/g;
  while ((match = bare.exec(content)) !== null) {
    urls.add(match[0].replace(/[.,;:]+$/, ""));
  }
  return [...urls];
}

export function isAwsUrl(url) {
  try {
    return AWS_HOST.test(new URL(url).hostname);
  } catch {
    return false;
  }
}

export function loadSourceLock(root) {
  const file = path.join(root, SOURCE_LOCK);
  if (!fs.existsSync(file)) return null;
  return new Set(extractUrls(fs.readFileSync(file, "utf8")).filter(isAwsUrl));
}

export function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};
  const data = {};
  for (const line of match[1].split("\n")) {
    const kv = line.match(/^(\w+):\s*(.+)$/);
    if (kv) data[kv[1]] = kv[2].trim().replace(/^["']|["']$/g, "");
  }
  return data;
}

export function needsReferences(relativePath, frontmatter) {
  if (frontmatter.draft === "true") return false;
  const posix = relativePath.split(path.sep).join("/");
  return CITED_SECTIONS.some((section) => posix.includes(section));
}

export function hasReferencesSection(content) {
  return /^##+\s+References\b/m.test(content);
}

function collectPages(docsRoot, projectRoot) {
  const pages = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.mdx?$/.test(entry.name)) {
        const content = fs.readFileSync(full, "utf8");
        pages.push({
          file: path.relative(projectRoot, full),
          content,
          frontmatter: parseFrontmatter(content),
        });
      }
    }
  };
  walk(docsRoot);
  return pages;
}

async function resolves(url) {
  try {
    const head = await fetch(url, { method: "HEAD", redirect: "follow" });
    if (head.ok) return { ok: true, status: head.status };
    const get = await fetch(url, { method: "GET", redirect: "follow" });
    return { ok: get.ok, status: get.status };
  } catch (error) {
    return { ok: false, status: 0, error: String(error.message || error) };
  }
}

async function main() {
  const root = path.resolve(import.meta.dirname, "..");
  const docs = path.join(root, "src/content/docs");

  if (!fs.existsSync(docs)) {
    console.log("check-references: no content yet, skipping");
    return;
  }

  const locked = loadSourceLock(root);
  if (!locked) {
    console.error(`check-references: ${SOURCE_LOCK} is missing`);
    process.exit(1);
  }

  const errors = [];
  const awsUrls = new Set();

  for (const page of collectPages(docs, root)) {
    if (needsReferences(page.file, page.frontmatter) && !hasReferencesSection(page.content)) {
      errors.push(`${page.file}: published page has no "## References" section`);
    }
    for (const url of extractUrls(page.content)) {
      if (!isAwsUrl(url)) continue;
      awsUrls.add(url);
      const normalized = url.replace(/#.*$/, "").replace(/\/$/, "");
      const inLock = [...locked].some(
        (source) => source.replace(/\/$/, "") === normalized || normalized.startsWith(source),
      );
      if (!inLock) {
        errors.push(`${page.file}: AWS link not in the source lock — ${url}`);
      }
    }
  }

  if (process.env.SKIP_LINK_CHECK === "1") {
    console.log("check-references: SKIP_LINK_CHECK=1, not resolving links");
  } else {
    const results = await Promise.all(
      [...awsUrls].map(async (url) => ({ url, result: await resolves(url) })),
    );
    for (const { url, result } of results) {
      if (!result.ok) {
        errors.push(
          `broken AWS link ${url} (HTTP ${result.status}${result.error ? `, ${result.error}` : ""})`,
        );
      }
    }
  }

  if (errors.length) {
    for (const error of errors) console.error(error);
    console.error(
      `\ncheck-references: ${errors.length} problem(s). Add new sources to ${SOURCE_LOCK} ` +
        "before citing them.",
    );
    process.exit(1);
  }
  console.log(`check-references: OK (${awsUrls.size} AWS link(s) checked)`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
