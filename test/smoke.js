#!/usr/bin/env node
/**
 * test/smoke.js
 *
 * Headless smoke test: loads the built bundle into a real Lua VM (fengari, a
 * Lua 5.3 interpreter) with the Roblox environment stubbed out by
 * test/stub.lua, boots the app, and drives the UI.
 *
 * Why: `npm run check` only proves the Luau is well formed. This proves it
 * actually *runs* - construction, controller wiring, tab switching, the
 * onboarding tour and unload - and the stub rejects invalid Instance members,
 * which is how the "TextLabel is not a valid member of Frame" class of bug gets
 * caught before it reaches Roblox.
 *
 * Caveat: the project is Luau, so compound assignments are rewritten to their
 * Lua 5.3 equivalent for the duration of this test only.
 *
 * Usage: npm test
 */
'use strict';

const fs = require('fs');
const path = require('path');

let fengari;
try {
  fengari = require('fengari');
} catch (error) {
  console.error('✗ fengari is not installed. Run: npm install');
  process.exit(2);
}

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const ROOT = path.join(__dirname, '..');
const BUNDLE = path.join(ROOT, 'dist', 'rick-morty-executor.lua');

if (!fs.existsSync(BUNDLE)) {
  console.error('✗ dist/rick-morty-executor.lua is missing. Run: npm run build');
  process.exit(2);
}

/** Luau-only syntax, rewritten for a plain Lua 5.3 parser. */
function toLua53(source) {
  return source.replace(/^(\s*)([\w.\[\]'"]+)\s*\+=\s*([^-\n][^\n]*?)\s*$/gm, '$1$2 = $2 + ($3)');
}

/* ------------------------------------------------- Lua <-> JS value bridge */

function luaToJs(L, index) {
  const type = lua.lua_type(L, index);

  switch (type) {
    case lua.LUA_NIL:
      return null;
    case lua.LUA_BOOLEAN:
      return lua.lua_toboolean(L, index);
    case lua.LUA_NUMBER:
      return lua.lua_tonumber(L, index);
    case lua.LUA_STRING:
      return to_jsstring(lua.lua_tostring(L, index));
    case lua.LUA_TABLE: {
      const absolute = lua.lua_absindex(L, index);
      const array = [];
      const object = {};
      let isArray = true;
      let count = 0;

      lua.lua_pushnil(L);
      while (lua.lua_next(L, absolute) !== 0) {
        const keyType = lua.lua_type(L, -2);
        const key = keyType === lua.LUA_STRING ? to_jsstring(lua.lua_tostring(L, -2)) : lua.lua_tonumber(L, -2);
        const value = luaToJs(L, -1);

        if (keyType === lua.LUA_NUMBER) array[key - 1] = value;
        else {
          isArray = false;
          object[key] = value;
        }

        count += 1;
        lua.lua_pop(L, 1);
      }

      if (count === 0) return {};
      return isArray ? array : object;
    }
    default:
      return null;
  }
}

function jsToLua(L, value) {
  if (value === null || value === undefined) {
    lua.lua_pushnil(L);
    return;
  }

  if (typeof value === 'boolean') {
    lua.lua_pushboolean(L, value);
    return;
  }

  if (typeof value === 'number') {
    lua.lua_pushnumber(L, value);
    return;
  }

  if (typeof value === 'string') {
    lua.lua_pushstring(L, to_luastring(value));
    return;
  }

  if (Array.isArray(value)) {
    lua.lua_createtable(L, value.length, 0);
    value.forEach((entry, index) => {
      jsToLua(L, entry);
      lua.lua_rawseti(L, -2, index + 1);
    });
    return;
  }

  const keys = Object.keys(value);
  lua.lua_createtable(L, 0, keys.length);
  for (const key of keys) {
    jsToLua(L, value[key]);
    lua.lua_setfield(L, -2, to_luastring(key));
  }
}

/* --------------------------------------------------------------------- main */

const stub = fs.readFileSync(path.join(__dirname, 'stub.lua'), 'utf8');
const assertions = fs.readFileSync(path.join(__dirname, 'assert.lua'), 'utf8');
const bundle = toLua53(fs.readFileSync(BUNDLE, 'utf8'));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const report = [];

lua.lua_pushjsfunction(L, (state) => {
  report.push(to_jsstring(lua.lua_tostring(state, 1)));
  return 0;
});
lua.lua_setglobal(L, to_luastring('__report'));

lua.lua_pushjsfunction(L, (state) => {
  lua.lua_pushstring(L, to_luastring(JSON.stringify(luaToJs(state, 1))));
  return 1;
});
lua.lua_setglobal(L, to_luastring('__jsonEncode'));

lua.lua_pushjsfunction(L, (state) => {
  const raw = lua.lua_tostring(state, 1);
  const parsed = JSON.parse(raw === null ? 'null' : to_jsstring(raw));
  jsToLua(state, parsed);
  return 1;
});
lua.lua_setglobal(L, to_luastring('__jsonDecode'));

console.log('\nRick & Morty AI Executor - headless smoke test');
console.log('='.repeat(58));

// Stub and bundle share one chunk so the entry point runs for real.
if (lauxlib.luaL_loadstring(L, to_luastring(`${stub}\n${bundle}`)) !== lua.LUA_OK) {
  console.error('✗ failed to compile the bundle: ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}

if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
  console.error('✗ the bundle threw while booting:');
  console.error('  ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}

lua.lua_setglobal(L, to_luastring('__APP'));

if (lauxlib.luaL_loadstring(L, to_luastring(assertions)) !== lua.LUA_OK) {
  console.error('✗ failed to compile the assertions: ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}

let failures = 0;
if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
  console.error('✗ the assertions threw:');
  console.error('  ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}

if (lua.lua_isnumber(L, -1)) {
  failures = lua.lua_tonumber(L, -1);
}
lua.lua_pop(L, 1);

console.log(report.join('\n'));
console.log('='.repeat(58));

if (failures > 0) {
  console.error(`✗ ${failures} check(s) failed\n`);
  process.exit(1);
}

console.log('✓ smoke test passed\n');
