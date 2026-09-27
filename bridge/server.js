#!/usr/bin/env node
/*
 * Rick & Morty AI Executor - Cowork bridge server.
 *
 * Runs the external high-fidelity interface on http://localhost:7896 and does
 * the actual API talking from Node, so Roblox's HTTP restrictions no longer
 * apply and API keys never leave this machine.
 *
 * Requires Node.js 18+ (global fetch).
 *
 *   node server.js
 *
 * Read-only API:
 *   GET  /                -> the interface
 *   GET  /api/status      -> provider/model/companion summary
 *   POST /api/chat        -> { messages: [{role, content}] } -> { text }
 *   POST /api/agent       -> multi-step plan + implement loop
 *   POST /api/freebuff    -> local open-access route
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const HERE = __dirname;
const CONFIG_PATH = path.join(HERE, 'config.json');
const INDEX_PATH = path.join(HERE, 'index.html');
const PORT = Number(process.env.RM_PORT || 7896);

/* --------------------------------------------------------------- config */

const FALLBACK_CONFIG = {
  provider: 'OpenRouter',
  style: 'openai',
  model: 'anthropic/claude-3.5-sonnet',
  url: 'https://openrouter.ai/api/v1/chat/completions',
  apiKey: '',
  companion: 'Rick',
  persona:
    "Act like Rick from the famous show 'Rick and Morty' when explaining, debugging, writing or editing code.",
  port: PORT,
};

function readConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    return { ...FALLBACK_CONFIG, ...JSON.parse(raw) };
  } catch (error) {
    return FALLBACK_CONFIG;
  }
}

/* ------------------------------------------------------------- payloads */

function lastUserContent(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === 'user') return messages[i].content;
  }
  return '';
}

function buildBody(messages, config) {
  const persona = config.persona || FALLBACK_CONFIG.persona;

  switch (config.style) {
    case 'anthropic':
      return {
        model: config.model,
        max_tokens: 4096,
        system: persona,
        messages: messages.filter((message) => message.role !== 'system'),
      };

    case 'agent':
      return {
        agent: 'default',
        prompt: lastUserContent(messages),
        system: persona,
        messages,
      };

    case 'freebuff':
      return {
        provider: 'freebuff',
        input: lastUserContent(messages),
        system: persona,
        messages,
      };

    default:
      return {
        model: config.model,
        messages: [{ role: 'system', content: persona }, ...messages],
      };
  }
}

function buildHeaders(config) {
  const headers = { 'Content-Type': 'application/json' };

  if (config.apiKey) {
    headers.Authorization = `Bearer ${config.apiKey}`;
    if (config.style === 'anthropic') headers['x-api-key'] = config.apiKey;
  }

  if (config.style === 'anthropic') headers['anthropic-version'] = '2023-06-01';
  if (config.provider === 'OpenRouter') {
    headers['HTTP-Referer'] = 'http://localhost:' + PORT;
    headers['X-Title'] = 'Rick & Morty AI Executor';
  }

  return headers;
}

const PRIORITY_KEYS = [
  'content',
  'text',
  'output',
  'response',
  'completion',
  'result',
  'answer',
  'message',
];

function deepFind(value, depth = 0) {
  if (depth > 6 || value == null) return null;
  if (typeof value === 'string') return value;
  if (typeof value !== 'object') return null;

  for (const key of PRIORITY_KEYS) {
    const candidate = value[key];
    if (typeof candidate === 'string' && candidate.trim() !== '') return candidate;
    if (candidate && typeof candidate === 'object') {
      const nested = deepFind(candidate, depth + 1);
      if (nested) return nested;
    }
  }

  if (Array.isArray(value) && value.length > 0) return deepFind(value[0], depth + 1);
  return null;
}

function parseResponse(raw, style) {
  let data;
  try {
    data = JSON.parse(raw);
  } catch (error) {
    return raw.trim();
  }

  if (data.error) {
    throw new Error(typeof data.error === 'string' ? data.error : data.error.message || 'Provider error');
  }

  let text = null;

  if (style === 'openai') {
    const choice = data.choices && data.choices[0];
    if (choice) text = (choice.message && choice.message.content) || choice.text;
  } else if (style === 'anthropic') {
    if (Array.isArray(data.content)) {
      text = data.content
        .filter((part) => part.type === 'text')
        .map((part) => part.text)
        .join('');
    }
    text = text || data.completion;
  } else {
    text = data.output || data.text || data.response || data.result;
  }

  text = text || deepFind(data);
  if (typeof text !== 'string' || text.trim() === '') {
    throw new Error('Could not locate assistant text in the provider response.');
  }

  return text;
}

async function callProvider(messages, config, overrides = {}) {
  const effective = { ...config, ...overrides };
  const started = Date.now();

  const response = await fetch(effective.url, {
    method: 'POST',
    headers: buildHeaders(effective),
    body: JSON.stringify(buildBody(messages, effective)),
  });

  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} from ${effective.provider}: ${raw.slice(0, 500)}`);
  }

  return { text: parseResponse(raw, effective.style), ms: Date.now() - started };
}

/* --------------------------------------------------------------- routes */

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 5e6) reject(new Error('payload too large'));
    });
    req.on('end', () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch (error) {
        reject(new Error('invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

async function handleChat(messages, config) {
  const result = await callProvider(messages, config);
  return { text: result.text, ms: result.ms, provider: config.provider, model: config.model };
}

async function handleAgent(messages, config) {
  // Multi-step development loop: plan first, then implement using that plan.
  const plan = await callProvider(
    [
      ...messages,
      {
        role: 'user',
        content:
          'Step 1 of 2 - planning. Reply with a short numbered implementation plan only. No code yet.',
      },
    ],
    config
  );

  const implementation = await callProvider(
    [
      ...messages,
      { role: 'assistant', content: plan.text },
      {
        role: 'user',
        content: 'Step 2 of 2 - implement that plan now. Return the complete Luau source in one ```lua block.',
      },
    ],
    config
  );

  return {
    text: `**Plan**\n\n${plan.text}\n\n**Implementation**\n\n${implementation.text}`,
    ms: plan.ms + implementation.ms,
    provider: config.provider,
    model: config.model,
    steps: 2,
  };
}

const server = http.createServer(async (req, res) => {
  const config = readConfig();
  const url = new URL(req.url, `http://localhost:${PORT}`);

  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      const html = fs.readFileSync(INDEX_PATH, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(html);
    }

    if (req.method === 'GET' && url.pathname === '/api/status') {
      return sendJson(res, 200, {
        ok: true,
        provider: config.provider,
        model: config.model,
        companion: config.companion,
        hasKey: Boolean(config.apiKey),
        port: PORT,
      });
    }

    if (req.method === 'POST' && url.pathname === '/api/chat') {
      const body = await readBody(req);
      return sendJson(res, 200, await handleChat(body.messages || [], config));
    }

    if (req.method === 'POST' && url.pathname === '/api/freebuff') {
      const body = await readBody(req);
      return sendJson(res, 200, await handleChat(body.messages || [], config));
    }

    if (req.method === 'POST' && url.pathname === '/api/agent') {
      const body = await readBody(req);
      return sendJson(res, 200, await handleAgent(body.messages || [], config));
    }

    sendJson(res, 404, { error: 'not found' });
  } catch (error) {
    sendJson(res, 502, { error: String((error && error.message) || error) });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  const config = readConfig();
  console.log('');
  console.log('  Rick & Morty AI Executor - Cowork bridge');
  console.log('  ------------------------------------------');
  console.log(`  interface : http://localhost:${PORT}`);
  console.log(`  provider  : ${config.provider} (${config.model})`);
  console.log(`  companion : ${config.companion}`);
  console.log(`  api key   : ${config.apiKey ? 'configured' : 'MISSING - set it in the Roblox UI'}`);
  console.log('');
  console.log('  Press Ctrl+C to stop.');
  console.log('');
});
