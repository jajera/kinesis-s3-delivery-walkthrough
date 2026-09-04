#!/usr/bin/env node
/**
 * Placeholder scanner — keeps real account identifiers out of published content.
 *
 * Scans fenced code blocks under src/content/docs for AWS account IDs, ARNs carrying a real
 * account, Lambda function URL ids, access key ids, and non-example email addresses.
 *
 * Prose outside fenced blocks is not scanned; a sentence mentioning an account is harmless,
 * a copy-paste command carrying one is not.
 *
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Documentation-safe account ids. */
const ALLOWED_ACCOUNTS = new Set(["123456789012", "987654321098"]);

/** Tokens that stand in for a real value. */
const PLACEHOLDER_TOKENS = ["ACCOUNT_ID", "REGION", "EXAMPLE", "your-", "my-"];

const RULES = [
  {
    name: "account id",
    re: /\b(\d{12})\b/g,
    ok: (match) => ALLOWED_ACCOUNTS.has(match[1]),
  },
  {
    name: "arn with real account",
    re: /arn:aws[a-z-]*:[a-z0-9-]+:[a-z0-9-]*:(\d{12}):[^\s`'"]+/gi,
    ok: (match) => ALLOWED_ACCOUNTS.has(match[1]),
  },
  {
    name: "access key id",
    re: /\b(AKIA|ASIA)[A-Z0-9]{16}\b/g,
    ok: () => false,
  },
  {
    name: "lambda function url",
    re: /\bhttps:\/\/[a-z0-9]{32,}\.lambda-url\.[a-z0-9-]+\.on\.aws\b/gi,
    ok: () => false,
  },
  {
    name: "non-example email",
    re: /\b[\w.+-]+@([\w-]+\.[\w.-]+)\b/g,
    ok: (match) => /(^|\.)example\.(com|org|net)$/i.test(match[1]),
  },
];

export function extractFencedBlocks(content) {
  const blocks = [];
  const re = /```[\w-]*[^\n]*\n([\s\S]*?)```/g;
  let match;
  while ((match = re.exec(content)) !== null) {
    const startLine = content.slice(0, match.index).split("\n").length;
    blocks.push({ text: match[1], startLine });
  }
  return blocks;
}

export function scanContent(content, fileLabel = "input") {
  const violations = [];
  for (const block of extractFencedBlocks(content)) {
    block.text.split("\n").forEach((line, offset) => {
      if (PLACEHOLDER_TOKENS.some((token) => line.includes(token))) return;
      for (const rule of RULES) {
        rule.re.lastIndex = 0;
        for (const match of line.matchAll(rule.re)) {
          if (!rule.ok(match)) {
            violations.push({
              file: fileLabel,
              line: block.startLine + offset,
              rule: rule.name,
              value: match[0],
            });
          }
        }
      }
    });
  }
  return violations;
}

export function scanFiles(docsRoot, projectRoot) {
  const violations = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.mdx?$/.test(entry.name)) {
        violations.push(
          ...scanContent(fs.readFileSync(full, "utf8"), path.relative(projectRoot, full)),
        );
      }
    }
  };
  walk(docsRoot);
  return violations;
}

function main() {
  const root = path.resolve(import.meta.dirname, "..");
  const docs = path.join(root, "src/content/docs");

  if (!fs.existsSync(docs)) {
    console.log("check-placeholders: no content yet, skipping");
    return;
  }

  const violations = scanFiles(docs, root);
  if (violations.length) {
    for (const v of violations) {
      console.error(`${v.file}:${v.line} ${v.rule} — ${v.value}`);
    }
    console.error(
      `\ncheck-placeholders: ${violations.length} violation(s). Use ACCOUNT_ID, REGION, ` +
        "123456789012, or an EXAMPLE-suffixed name. See .kiro/steering/editor-tooling.md.",
    );
    process.exit(1);
  }
  console.log("check-placeholders: OK");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
