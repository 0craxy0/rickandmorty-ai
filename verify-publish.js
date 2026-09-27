#!/usr/bin/env node
/**
 * Rick & Morty AI Executor - publish check.
 *
 * Closes the loop between the install one-liners the README prints and what
 * GitHub actually serves: it reads the URLs out of the README's install block,
 * requests each one, and compares the bytes with the locally built bundle.
 *
 * Why this exists: `loadstring` downloads from GitHub at run time, so a build
 * that is correct on disk but never pushed is still broken for every user. Both
 * failures seen in this project were invisible locally - a fix sitting in an
 * unpushed commit, and a raw CDN edge serving the commit before it.
 *
 * It tries to tell those three apart:
 *   - 404            the tag or branch does not have the file (push it)
 *   - differs        the remote build is not this build (commit + push)
 *   - stale edge     the push is fine, the CDN copy is old (re-run shortly)
 *
 * Needs network access. Usage:
 *   npm run verify:publish
 *
 * Set GITHUB_TOKEN to raise the GitHub API rate limit when checking the
 * "differs" case.
 */
'use strict';

const fs = require('fs');
const path = require('path');

// build.js holds the single source of truth for the install URLs.
const build = require('./build.js');

const ROOT = __dirname;
const README_PATH = path.join(ROOT, 'README.md');
const TIMEOUT_MS = 20000;

const failures = [];
const notes = [];

function pass(message) {
  console.log('PASS  ' + message);
}

function fail(message) {
  failures.push(message);
  console.log('FAIL  ' + message);
}

function note(message) {
  notes.push(message);
}

/** The install one-liners exactly as the README prints them. */
function documentedUrls() {
  let readme;
  try {
    readme = fs.readFileSync(README_PATH, 'utf8');
  } catch (error) {
    return null;
  }

  const start = readme.indexOf(build.BEGIN_MARK);
  const end = readme.indexOf(build.END_MARK);
  if (start === -1 || end === -1) return null;

  const block = readme.slice(start, end);
  const pattern = /loadstring\(game:HttpGet\("([^"]+)"\)\)\(\)/g;
  const urls = [];
  let match;

  while ((match = pattern.exec(block)) !== null) urls.push(match[1]);
  return urls;
}

async function request(url, method) {
  return fetch(url, {
    method,
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: process.env.GITHUB_TOKEN ? { authorization: `Bearer ${process.env.GITHUB_TOKEN}` } : {},
  });
}

/** raw.githubusercontent.com/<owner>/<repo>/<ref>/<path> -> { owner, repo, ref, file } */
function splitRawUrl(url) {
  const match = String(url).match(/^https:\/\/raw\.githubusercontent\.com\/([^/]+)\/([^/]+)\/([^/]+)\/(.+)$/);
  if (!match) return null;
  return { owner: match[1], repo: match[2], ref: match[3], file: match[4] };
}

/**
 * The same file at the same ref, read through the API instead of the raw CDN.
 * The API is authoritative for a commit; the raw endpoint is a cache in front
 * of it, which is what makes a stale edge distinguishable from a bad push.
 */
async function apiCopy(url) {
  const parts = splitRawUrl(url);
  if (!parts) return { content: null, error: 'unrecognised URL' };

  const endpoint = `https://api.github.com/repos/${parts.owner}/${parts.repo}/contents/${parts.file}?ref=${encodeURIComponent(parts.ref)}`;

  try {
    const response = await request(endpoint, 'GET');
    if (!response.ok) return { content: null, error: `HTTP ${response.status}` };

    const body = await response.json();
    if (!body || typeof body.content !== 'string') return { content: null, error: 'no content field' };

    return { content: Buffer.from(body.content, 'base64'), error: null };
  } catch (error) {
    return { content: null, error: error.message };
  }
}

/** What to do about a 404, told apart by which URL it is. */
function pushHint(url, coords) {
  if (coords && url.includes(`/v${coords.version}/`)) {
    return `tag v${coords.version} is not on the remote yet - git push origin v${coords.version}`;
  }
  return `the branch ${coords ? coords.branch : 'main'} does not have this file yet - commit and push`;
}

function nameFor(url, coords) {
  if (!coords) return 'documented';
  return url.includes(`/v${coords.version}/`) ? `pinned (v${coords.version})` : `latest (${coords.branch})`;
}

/** Drifting is a release problem for a tag and a push problem for a branch. */
function driftHint(url, coords) {
  if (coords && url.includes(`/v${coords.version}/`)) {
    return `release v${coords.version} predates this build - bump the version, or move the tag with: git push --force origin v${coords.version}`;
  }
  return 'run: npm run build && git add dist/ && git push';
}

function finish() {
  console.log('==========================================================');

  if (notes.length > 0) {
    console.log('');
    for (const message of notes) console.log('INFO  ' + message);
  }

  console.log('');
  if (failures.length > 0) {
    console.error(`✗ ${failures.length} publish problem(s)\n`);
    process.exit(1);
  }

  console.log('✓ publish check passed\n');
}

async function checkUrl(url, local, derived) {
  const coords = derived ? derived.coords : null;
  const name = nameFor(url, coords);
  let head;

  try {
    head = await request(url, 'HEAD');
  } catch (error) {
    fail(`${name}: could not reach GitHub (${error.message}) - offline?`);
    return;
  }

  if (head.status === 404) {
    fail(`${name}: HTTP 404 - ${pushHint(url, coords)}`);
    return;
  }

  if (!head.ok) {
    fail(`${name}: HTTP ${head.status}`);
    return;
  }

  let remote;
  try {
    const response = await request(url, 'GET');
    remote = Buffer.from(await response.arrayBuffer());
  } catch (error) {
    fail(`${name}: HEAD said ${head.status} but the download failed (${error.message})`);
    return;
  }

  if (remote.equals(local)) {
    pass(`${name}: HTTP 200, byte-identical to dist/ (${local.length} bytes)`);
    return;
  }

  const api = await apiCopy(url);

  if (api.content && api.content.equals(local)) {
    fail(`${name}: serving ${remote.length} bytes, not this build - GitHub's raw CDN is holding a stale edge copy`);
    note('the push itself is correct (the API at that ref matches dist/) - this clears in a few minutes, re-run then');
    return;
  }

  if (api.content) {
    fail(`${name}: serves a different build than dist/ (${remote.length} vs ${local.length} bytes) - ${driftHint(url, coords)}`);
    note(`the API at that ref also differs, so this is not a cache: ${url}`);
    return;
  }

  fail(`${name}: serves ${remote.length} bytes, not this build (${local.length}) - and the API could not confirm why (${api.error})`);
}

async function main() {
  console.log('\nRick & Morty AI Executor - publish check');
  console.log('='.repeat(58));

  if (!fs.existsSync(build.OUT_FILE)) {
    fail(`dist/${build.OUT_FILE_NAME} is missing - run: npm run build`);
    return finish();
  }

  const local = fs.readFileSync(build.OUT_FILE);
  const urls = documentedUrls();

  if (!urls || urls.length === 0) {
    fail(`README has no ${build.BEGIN_MARK} / ${build.END_MARK} block containing a loadstring one-liner`);
    return finish();
  }

  const derived = build.rawUrls();

  // The check is only meaningful when it verifies the URLs the build would
  // write, so a drifted README is reported before anything is requested.
  if (derived) {
    const expected = [derived.latest, derived.pinned].sort();
    const documented = [...urls].sort();

    if (documented.join('\n') !== expected.join('\n')) {
      fail('the README install block does not match package.json - run: npm run build');
      note('documented: ' + documented.join(', '));
      note('expected  : ' + expected.join(', '));
      return finish();
    }
  } else {
    note('package.json has no usable repository field - verifying the README URLs as written');
  }

  for (const url of urls) {
    await checkUrl(url, local, derived);
  }

  return finish();
}

module.exports = { checkUrl, apiCopy, documentedUrls, splitRawUrl, nameFor, pushHint, driftHint };

if (require.main === module) {
  main().catch((error) => {
    console.error('✗ publish check crashed: ' + (error && error.stack ? error.stack : error));
    process.exit(1);
  });
}
