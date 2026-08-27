#!/usr/bin/env node
/**
 * Force OpenWhispr preferredLanguage=en in Chromium localStorage (leveldb).
 * Safe to run while OpenWhispr is stopped; skips if leveldb is locked.
 */
import { createRequire } from "node:module";
import path from "node:path";
import os from "node:os";

const require = createRequire(import.meta.url);
const toolsDir = path.join(path.dirname(new URL(import.meta.url).pathname), ".openwhispr-tools");

async function loadClassicLevel() {
  try {
    return require("classic-level").ClassicLevel;
  } catch {
    const { execFileSync } = await import("node:child_process");
    execFileSync("npm", ["install", "--prefix", toolsDir, "classic-level@3"], {
      stdio: "ignore",
    });
    return require(path.join(toolsDir, "node_modules/classic-level")).ClassicLevel;
  }
}

const userData = process.env.OPENWHISPR_USER_DATA
  || path.join(os.homedir(), ".config/open-whispr");
const dbPath = path.join(userData, "Local Storage", "leveldb");
const storageKey = Buffer.from("_file://\x00\x01preferredLanguage", "latin1");
const storageVal = Buffer.from("\x01en", "latin1");

async function leveldbLockedByOpenWhispr() {
  try {
    const { execFileSync } = await import("node:child_process");
    const out = execFileSync("fuser", [path.join(dbPath, "LOCK")], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (!out) return false;
    for (const pid of out.split(/\s+/)) {
      try {
        const cmd = execFileSync("ps", ["-p", pid, "-o", "comm="], {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
        }).trim();
        if (/open-whispr/i.test(cmd)) return true;
      } catch {
        /* process gone */
      }
    }
    return false;
  } catch {
    return false;
  }
}

async function main() {
  if (await leveldbLockedByOpenWhispr()) {
    process.exit(0);
  }

  const ClassicLevel = await loadClassicLevel();
  const db = new ClassicLevel(dbPath, { createIfMissing: false });
  try {
    await db.open();
    const existing = await db.get(storageKey).catch(() => null);
    if (existing?.equals(storageVal)) {
      return;
    }
    await db.put(storageKey, storageVal);
    console.log("openwhispr-ensure-english: preferredLanguage=en");
  } finally {
    await db.close().catch(() => {});
  }
}

main().catch((err) => {
  console.error(`openwhispr-ensure-english: ${err.message}`);
  process.exit(1);
});
