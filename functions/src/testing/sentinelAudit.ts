import {readdirSync, readFileSync} from "node:fs";
import {join, resolve, sep} from "node:path";

/**
 * A lexical audit of every `FieldValue.delete()` in the Functions source.
 *
 * This exists because the defect it looks for cannot be found any other way. A
 * sentinel is legal in `update()` and in `set(..., {merge: true})` and rejected
 * outright by `create()` and by `set()` without a merge, and nothing but a real
 * write can tell the difference: the payload is a plain object until Firestore
 * serializes it, so the compiler, the linter, and every pure test pass. One such
 * sentinel sat in a shared create/update payload and made the sale
 * reconciliation trigger throw on every sale for as long as it existed.
 *
 * The audit reads source text rather than running anything, so it is an
 * approximation - but the assertion that matters does not depend on the fuzzy
 * part. Whether a sentinel sits inside a `create(...)` or an unmerged `set(...)`
 * is decided by bracket matching alone, which is exact. Only `owner`, the name
 * of the enclosing declaration, is a best-effort label, and it is used solely to
 * give the reviewed-payload list keys that survive an edit above them.
 */

/** Where a sentinel ends up, and therefore whether it is legal. */
export type SentinelVerdict =
  /** Inside `update(...)`. Always legal. */
  | "update"
  /** Inside `set(..., {merge: true})`. Legal. */
  | "set_merge"
  /** Inside `create(...)`. Rejected by Firestore. */
  | "create"
  /** Inside `set(...)` with no `{merge: true}`. Rejected by Firestore. */
  | "set_without_merge"
  /**
   * In a payload that is not written where it is built, so the write kind can
   * only be established by reading the call sites. This is the shape the
   * original defect had, which is why every one of these is enumerated in the
   * test's reviewed list rather than assumed safe.
   */
  | "unattached";

export interface SentinelSite {
  /** Path relative to `functions/src`, with forward slashes. */
  file: string;
  line: number;
  verdict: SentinelVerdict;
  /** Enclosing `function`/`const` name, or `""` at the top level. */
  owner: string;
}

const SENTINEL = "FieldValue.delete()";
const WRITE_METHOD = /(?:^|\.)(create|set|update)$/;

/**
 * Blanks out comments and string bodies while preserving every offset, so that
 * bracket matching and the declaration scan cannot be fooled by prose. The
 * sentinel is named in several comments in this repository, and one of those
 * comments is in the very function whose defect started this audit.
 */
function blankNonCode(source: string): string {
  const out = source.split("");
  let index = 0;
  const end = source.length;

  const blankTo = (stop: number): void => {
    while (index < stop && index < end) {
      if (source[index] !== "\n") out[index] = " ";
      index += 1;
    }
  };

  while (index < end) {
    const pair = source.slice(index, index + 2);
    if (pair === "//") {
      const newline = source.indexOf("\n", index);
      blankTo(newline === -1 ? end : newline);
      continue;
    }
    if (pair === "/*") {
      const close = source.indexOf("*/", index + 2);
      blankTo(close === -1 ? end : close + 2);
      continue;
    }
    const character = source[index];
    if (character === "\"" || character === "'" || character === "`") {
      index += 1;
      while (index < end) {
        if (source[index] === "\\") {
          out[index] = " ";
          if (index + 1 < end && source[index + 1] !== "\n") out[index + 1] = " ";
          index += 2;
          continue;
        }
        if (source[index] === character) {
          index += 1;
          break;
        }
        if (source[index] !== "\n") out[index] = " ";
        index += 1;
      }
      continue;
    }
    index += 1;
  }
  return out.join("");
}

/** The identifier immediately to the left of `index`, e.g. `transaction.create`. */
function identifierBefore(source: string, index: number): string {
  let cursor = index - 1;
  while (cursor >= 0 && /\s/.test(source[cursor])) cursor -= 1;
  const end = cursor + 1;
  while (cursor >= 0 && /[A-Za-z0-9_$.\]]/.test(source[cursor])) cursor -= 1;
  return source.slice(cursor + 1, end);
}

/** Splits an argument list at top-level commas only. */
function splitArguments(text: string): string[] {
  const args: string[] = [];
  let depth = 0;
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if ("([{".includes(character)) depth += 1;
    else if (")]}".includes(character)) depth -= 1;
    else if (character === "," && depth === 0) {
      args.push(text.slice(start, index));
      start = index + 1;
    }
  }
  args.push(text.slice(start));
  return args.map((argument) => argument.trim()).filter((argument) => argument.length > 0);
}

interface CallFrame {
  name: string;
  open: number;
}

/**
 * The declaration each `{` belongs to, so a sentinel can be attributed to the
 * function that builds it. A brace opened while a parameter list is still open -
 * a destructured parameter - is not a body, so it must not consume the name.
 */
function declarationStarts(code: string): Map<number, string> {
  const starts = new Map<number, string>();
  const patterns = [
    /\bfunction\s+([A-Za-z0-9_$]+)/g,
    /\b(?:const|let|var|class)\s+([A-Za-z0-9_$]+)/g,
  ];
  for (const pattern of patterns) {
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(code)) !== null) {
      starts.set(match.index, match[1]);
    }
  }
  return starts;
}

function auditSource(code: string, relativePath: string): SentinelSite[] {
  const declarations = declarationStarts(code);
  const sites: SentinelSite[] = [];
  const calls: CallFrame[] = [];
  const scopes: string[] = [];
  let pendingName = "";
  let index = 0;
  let line = 1;

  while (index < code.length) {
    const character = code[index];
    if (character === "\n") {
      line += 1;
      index += 1;
      continue;
    }
    const declared = declarations.get(index);
    if (declared !== undefined) pendingName = declared;

    if (code.startsWith(SENTINEL, index)) {
      const writes = calls.filter((call) => WRITE_METHOD.test(call.name));
      const innermost = writes[writes.length - 1];
      const owner = [...scopes].reverse().find((name) => name.length > 0) ?? "";
      sites.push({
        file: relativePath,
        line,
        owner,
        verdict: innermost === undefined ?
          "unattached" :
          verdictForWrite(code, innermost),
      });
      index += SENTINEL.length;
      continue;
    }
    if (character === "(") {
      calls.push({name: identifierBefore(code, index), open: index});
      index += 1;
      continue;
    }
    if (character === ")") {
      calls.pop();
      index += 1;
      continue;
    }
    if (character === "{") {
      // Inside an open argument or parameter list this brace is an inline type,
      // a destructuring pattern, or a callback body - never the declaration's
      // own body - so the pending name still belongs to the body still to come.
      // `function progressData(options: {phase: string}): DocumentData {` needs
      // exactly this, or its name is eaten by its own parameter type.
      if (calls.length > 0) {
        scopes.push("");
      } else {
        scopes.push(pendingName);
        pendingName = "";
      }
      index += 1;
      continue;
    }
    if (character === "}") {
      scopes.pop();
      index += 1;
      continue;
    }
    // A statement that ended without opening a body - `const update = {...};` -
    // has no name left to give, and leaving it pending would mislabel the next
    // block that does open one.
    if (character === ";" && calls.length === 0) pendingName = "";
    index += 1;
  }
  return sites;
}

/** The `)` matching the `(` at `open`, or the end of the source. */
function matchingParen(code: string, open: number): number {
  let depth = 0;
  for (let index = open; index < code.length; index += 1) {
    if (code[index] === "(") depth += 1;
    else if (code[index] === ")") {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return code.length;
}

function verdictForWrite(code: string, call: CallFrame): SentinelVerdict {
  const method = call.name.split(".").pop() ?? "";
  if (method === "update") return "update";
  if (method === "create") return "create";
  // The closing paren is still ahead of the sentinel that triggered this call,
  // so the frame has no `close` yet and the argument list has to be matched here.
  const args = splitArguments(code.slice(call.open + 1, matchingParen(code, call.open)));
  const options = args[args.length - 1] ?? "";
  return /^\{[^{}]*\bmerge\s*:\s*true\b[^{}]*\}$/.test(options) ?
    "set_merge" :
    "set_without_merge";
}

function typescriptFiles(root: string, prefix = ""): string[] {
  const files: string[] = [];
  for (const entry of readdirSync(root, {withFileTypes: true})) {
    const relative = prefix.length > 0 ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      // `testing/` is the audit's own support code, and a `*.test.ts` file
      // asserts about sentinels rather than writing one. Neither reaches
      // Firestore, and including them would make the reviewed list a list of
      // test helpers instead of production payload builders.
      if (entry.name === "testing") continue;
      files.push(...typescriptFiles(join(root, entry.name), relative));
      continue;
    }
    if (!entry.name.endsWith(".ts")) continue;
    if (entry.name.endsWith(".test.ts")) continue;
    files.push(relative);
  }
  return files;
}

/** `functions/src`, resolved from this module wherever it is compiled to. */
export function functionsSourceRoot(): string {
  const here = resolve(__dirname);
  const marker = `${sep}functions${sep}`;
  const at = here.lastIndexOf(marker);
  if (at === -1) throw new Error(`Cannot locate functions/src from ${here}`);
  return join(here.slice(0, at + marker.length), "src");
}

/**
 * Classifies one piece of source text. Exported so the classifier can be tested
 * against known-good and known-bad snippets: a guard nobody has watched fail is
 * not yet a guard.
 */
export function classifyDeleteSentinels(
  source: string,
  file = "<memory>"
): SentinelSite[] {
  return auditSource(blankNonCode(source), file);
}

/** Every `FieldValue.delete()` under `root`, classified by the write it reaches. */
export function auditDeleteSentinels(root = functionsSourceRoot()): SentinelSite[] {
  const sites: SentinelSite[] = [];
  for (const relative of typescriptFiles(root).sort()) {
    const source = readFileSync(join(root, relative.split("/").join(sep)), "utf8");
    sites.push(...auditSource(blankNonCode(source), relative));
  }
  return sites;
}

/** The sites Firestore would reject. Empty is the only acceptable result. */
export function illegalSentinelSites(sites: readonly SentinelSite[]): SentinelSite[] {
  return sites.filter(
    (site) => site.verdict === "create" || site.verdict === "set_without_merge"
  );
}
