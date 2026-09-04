#!/usr/bin/env node
/**
 * Aside validator — keeps the callout vocabulary small so readers learn what each one means.
 *
 * Allowed: tip, caution, danger, note.
 *   tip     — suggestion or shortcut
 *   note    — context worth knowing, including "Evidence TODO" markers during authoring
 *   caution — easy to get wrong, or a wait the reader should not mistake for a failure
 *   danger  — cost, data loss, or credential exposure
 *
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ALLOWED = new Set(["tip", "note", "caution", "danger"]);

export function validateAsides(content, fileLabel = "input") {
  const violations = [];
  content.split("\n").forEach((line, index) => {
    const match = line.match(/^:::([a-z]+)\b/);
    if (match && !ALLOWED.has(match[1])) {
      violations.push({ file: fileLabel, line: index + 1, type: match[1] });
    }
  });
  return violations;
}

export function scanAsideFiles(docsRoot, projectRoot) {
  const violations = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (/\.mdx?$/.test(entry.name)) {
        violations.push(
          ...validateAsides(fs.readFileSync(full, "utf8"), path.relative(projectRoot, full)),
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
    console.log("check-asides: no content yet, skipping");
    return;
  }

  const violations = scanAsideFiles(docs, root);
  if (violations.length) {
    for (const v of violations) {
      console.error(`${v.file}:${v.line} disallowed aside ":::${v.type}"`);
    }
    console.error(`\ncheck-asides: allowed types are ${[...ALLOWED].join(", ")}.`);
    process.exit(1);
  }
  console.log("check-asides: OK");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
