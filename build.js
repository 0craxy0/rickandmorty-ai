#!/usr/bin/env node
/**
 * Rick & Morty AI Executor — build tool.
 *
 * Roblox executors consume a single chunk, so this bundles every module under
 * `src/` into one pasteable file at `dist/rick-morty-executor.lua`.
 *
 * Modules are plain Luau files that `return` a table and call
 * `require("core/Example")`. The bundle installs a tiny module registry so the
 * exact same source runs unbundled inside a dev harness.
 *
 * Files under `bridge/` are inlined as raw text assets (see `bundle/assets`).
 *
 * Usage:
 *   node build.js           validate + bundle
 *   node build.js --check   validate only
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const SRC = path.join(ROOT, 'src');
const BRIDGE = path.join(ROOT, 'bridge');
const DIST = path.join(ROOT, 'dist');
const ENTRY = 'init';
const OUT_FILE = path.join(DIST, 'rick-morty-executor.lua');

const checkOnly = process.argv.includes('--check');

/* ------------------------------------------------------------------ files */

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

function moduleId(file) {
  return path.relative(SRC, file).replace(/\\/g, '/').replace(/\.lua$/, '');
}

function countNewlines(text) {
  let count = 0;
  for (let i = 0; i < text.length; i++) if (text[i] === '\n') count++;
  return count;
}

/* -------------------------------------------------------------- tokenizer */

/**
 * Minimal Luau tokenizer. Strips comments and strings so the block checker
 * below never mistakes their contents for keywords.
 */
function tokenize(source, file) {
  const tokens = [];
  const length = source.length;
  let index = 0;
  let line = 1;

  const longBracket = (at) => {
    if (source[at] !== '[') return null;
    let cursor = at + 1;
    let level = 0;
    while (source[cursor] === '=') {
      level++;
      cursor++;
    }
    if (source[cursor] !== '[') return null;
    return { level, contentStart: cursor + 1 };
  };

  while (index < length) {
    const char = source[index];

    if (char === '\n') {
      line++;
      index++;
      continue;
    }
    if (char === ' ' || char === '\t' || char === '\r') {
      index++;
      continue;
    }

    // Comments (line, long) and long strings share the `[=*[` delimiter.
    if (char === '-' && source[index + 1] === '-') {
      const bracket = longBracket(index + 2);
      if (bracket) {
        const close = ']' + '='.repeat(bracket.level) + ']';
        const end = source.indexOf(close, bracket.contentStart);
        if (end === -1) return { error: `${file}:${line}: unterminated long comment` };
        line += countNewlines(source.slice(index, end + close.length));
        index = end + close.length;
      } else {
        while (index < length && source[index] !== '\n') index++;
      }
      continue;
    }

    if (char === '[') {
      const bracket = longBracket(index);
      if (bracket) {
        const close = ']' + '='.repeat(bracket.level) + ']';
        const end = source.indexOf(close, bracket.contentStart);
        if (end === -1) return { error: `${file}:${line}: unterminated long string` };
        line += countNewlines(source.slice(index, end + close.length));
        index = end + close.length;
        continue;
      }
    }

    if (char === '"' || char === "'") {
      let cursor = index + 1;
      while (cursor < length) {
        if (source[cursor] === '\\') {
          cursor += 2;
          continue;
        }
        if (source[cursor] === char) break;
        if (source[cursor] === '\n') return { error: `${file}:${line}: unterminated string` };
        cursor++;
      }
      if (cursor >= length) return { error: `${file}:${line}: unterminated string` };
      index = cursor + 1;
      continue;
    }

    if (/[A-Za-z_]/.test(char)) {
      let cursor = index;
      while (cursor < length && /[A-Za-z0-9_]/.test(source[cursor])) cursor++;
      tokens.push({ type: 'name', value: source.slice(index, cursor), line });
      index = cursor;
      continue;
    }

    if (/[0-9]/.test(char) || (char === '.' && /[0-9]/.test(source[index + 1] || ''))) {
      let cursor = index;
      while (cursor < length && /[0-9a-fA-FxX._]/.test(source[cursor])) cursor++;
      tokens.push({ type: 'number', value: source.slice(index, cursor), line });
      index = cursor;
      continue;
    }

    tokens.push({ type: 'symbol', value: char, line });
    index++;
  }

  return { tokens };
}

/* ------------------------------------------------------------ validation */

const PAIRS = { '(': ')', '[': ']', '{': '}' };

function validate(file, source) {
  const scanned = tokenize(source, file);
  if (scanned.error) return [scanned.error];

  const errors = [];
  const tokens = scanned.tokens;
  const blocks = [];
  const brackets = [];

  // `for`/`while` are closed by the `do` that opens their body, so the very
  // next `do` keyword is already accounted for.
  let pendingDo = 0;

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];

    if (token.type === 'symbol') {
      if (PAIRS[token.value]) {
        brackets.push(token);
      } else if (token.value === ')' || token.value === ']' || token.value === '}') {
        const open = brackets.pop();
        if (!open || PAIRS[open.value] !== token.value) {
          errors.push(`${file}:${token.line}: unbalanced '${token.value}'`);
        }
      }
      continue;
    }

    if (token.type !== 'name') continue;

    switch (token.value) {
      case 'function':
      case 'if':
        blocks.push({ open: token.value, line: token.line });
        break;
      case 'for':
      case 'while':
        blocks.push({ open: token.value, line: token.line });
        pendingDo++;
        break;
      case 'do':
        if (pendingDo > 0) pendingDo--;
        else blocks.push({ open: 'do', line: token.line });
        break;
      case 'repeat':
        blocks.push({ open: 'repeat', line: token.line });
        break;
      case 'end': {
        const top = blocks.pop();
        if (!top) errors.push(`${file}:${token.line}: unexpected 'end'`);
        else if (top.open === 'repeat') {
          errors.push(`${file}:${token.line}: 'repeat' at line ${top.line} closed by 'end'`);
        }
        break;
      }
      case 'until': {
        const top = blocks.pop();
        if (!top || top.open !== 'repeat') {
          errors.push(`${file}:${token.line}: unexpected 'until'`);
        }
        break;
      }
      default:
        break;
    }
  }

  for (const bracket of brackets) {
    errors.push(`${file}:${bracket.line}: unclosed '${bracket.value}'`);
  }
  for (const block of blocks) {
    errors.push(`${file}:${block.line}: '${block.open}' is never closed`);
  }

  if (/\breturn\b/.test(source.replace(/--.*$/gm, '')) === false) {
    errors.push(`${file}: module has no return statement`);
  }

  // Accidental globals: `function name()` without `local` leaks into _G. Table
  // methods (`function Table.name()`) are the intended style and stay fine.
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.type !== 'name' || token.value !== 'function') continue;

    const previous = tokens[i - 1];
    const target = tokens[i + 1];
    const afterTarget = tokens[i + 2];

    if (afterTarget && (afterTarget.value === '.' || afterTarget.value === ':')) continue;

    const isLocal = previous && previous.type === 'name' && previous.value === 'local';
    const isExpression =
      previous && previous.type === 'symbol' && ['=', '(', ',', '{', 'return'].includes(previous.value);

    if (!isLocal && !isExpression && target && target.type === 'name') {
      errors.push(`${file}:${token.line}: 'function ${target.value}()' is a global - add \`local\``);
    }
  }

  return errors;
}

/** Every require("id") must resolve to a real module. */
function validateRequires(file, source, knownIds) {
  const errors = [];
  const pattern = /require\(\s*["']([^"']+)["']\s*\)/g;
  let match;

  while ((match = pattern.exec(source)) !== null) {
    const id = match[1];
    if (knownIds.has(id)) continue;
    const line = source.slice(0, match.index).split('\n').length;
    errors.push(`${file}:${line}: require("${id}") does not resolve to a module`);
  }

  return errors;
}

/* ---------------------------------------------------------------- bundler */

function toLongString(content) {
  let level = 1;
  while (content.includes(']' + '='.repeat(level) + ']')) level++;
  const equals = '='.repeat(level);
  return `[${equals}[\n${content.trim()}\n]${equals}]`;
}

function buildBridgeAssets() {
  const files = walk(BRIDGE).filter((file) => !file.endsWith('.md'));
  if (files.length === 0) return null;

  const entries = files
    .map((file) => {
      const id = path.relative(ROOT, file).replace(/\\/g, '/');
      const content = fs.readFileSync(file, 'utf8');
      return `\t[${JSON.stringify(id)}] = ${toLongString(content)},`;
    })
    .join('\n');

  return `__modules["bundle/assets"] = function(require)\n\t-- Raw text assets inlined from /bridge.\n\treturn {\n${entries}\n\t}\nend\n`;
}

function bundle(files) {
  const banner = `--[[
\tRick & Morty AI Executor — bundled build
\tGenerated by build.js from /src. Do not edit this file by hand.
\tPaste the whole chunk into an executor and run it.

\tQuick menu : press ';'   |  Dashboard: run RickMortyAI:Open()  |  Unload: RickMortyAI:Unload()
]]

--!nonstrict

local __modules, __cache = {}, {}

__modules["__root"] = function(require)
\treturn require
end

`;

  const modules = files
    .map((file) => {
      const id = moduleId(file);
      const body = fs
        .readFileSync(file, 'utf8')
        .replace(/^\uFEFF/, '')
        .trimEnd();
      return `__modules[${JSON.stringify(id)}] = function(require)\n${body}\nend\n`;
    })
    .join('\n');

  const runtime = `
local function __require(id)
\tlocal cached = __cache[id]
\tif cached ~= nil then
\t\treturn cached
\tend

\tlocal loader = __modules[id]
\tif not loader then
\t\terror("[RickMortyAI] module not found: " .. tostring(id), 2)
\tend

\tlocal result = loader(__require)
\t__cache[id] = result == nil and true or result
\treturn result
end

`;

  const bridge = buildBridgeAssets();
  return `${banner}${modules}\n${bridge ? bridge + '\n' : ''}${runtime}return __require(${JSON.stringify(ENTRY)})\n`;
}

/* ------------------------------------------------------------------- main */

function main() {
  const files = walk(SRC)
    .filter((file) => file.endsWith('.lua'))
    .sort();

  if (files.length === 0) {
    console.error('✗ no Luau modules found under src/');
    process.exit(1);
  }

  const knownIds = new Set([ENTRY, 'bundle/assets']);
  for (const file of files) knownIds.add(moduleId(file));

  const errors = [];
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    const id = moduleId(file) + '.lua';
    errors.push(...validate(id, source));
    errors.push(...validateRequires(id, source, knownIds));
  }

  if (errors.length > 0) {
    console.error(`✗ ${errors.length} validation problem(s):`);
    for (const error of errors) console.error('  - ' + error);
    process.exit(1);
  }

  console.log(`✓ validated ${files.length} modules`);

  if (checkOnly) return;

  // Every module must be reachable from the entry point.
  const source = files.map((file) => fs.readFileSync(file, 'utf8')).join('\n');
  for (const file of files) {
    const id = moduleId(file);
    if (id === ENTRY || id.startsWith('bundle/')) continue;
    const referenced =
      source.includes(`require("${id}")`) || source.includes(`require('${id}')`);
    if (!referenced) console.warn(`  ! ${id} is not required by any module`);
  }

  if (!fs.existsSync(DIST)) fs.mkdirSync(DIST, { recursive: true });
  fs.writeFileSync(OUT_FILE, bundle(files), 'utf8');

  const size = (fs.statSync(OUT_FILE).size / 1024).toFixed(1);
  console.log(`✓ wrote dist/rick-morty-executor.lua (${size} kB)`);
}

main();
