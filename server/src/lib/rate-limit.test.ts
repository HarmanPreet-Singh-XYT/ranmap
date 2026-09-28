import assert from "node:assert/strict";
import { test } from "node:test";
import type { NextFunction, Request, Response } from "express";
import {
  memoryRateLimitStore,
  rateLimit,
  setRateLimitStore,
} from "./rate-limit.js";

/** Builds a minimal Express req/res pair for exercising middleware directly. */
function harness() {
  const state = {
    statusCode: 200,
    headers: {} as Record<string, string>,
    body: undefined as unknown,
    nextCalls: 0,
  };
  const req = { ip: "203.0.113.7", headers: {}, body: {} } as unknown as Request;
  const res = {
    setHeader(name: string, value: string) {
      state.headers[name.toLowerCase()] = value;
      return res;
    },
    status(code: number) {
      state.statusCode = code;
      return res;
    },
    json(body: unknown) {
      state.body = body;
      return res;
    },
  } as unknown as Response;
  const next = (() => {
    state.nextCalls += 1;
  }) as NextFunction;
  return { req, res, state, next };
}

/** A unique bucket name per test so the shared in-memory store can't bleed. */
let seq = 0;
const uniqueName = () => `test-${++seq}-${Math.random().toString(36).slice(2)}`;

test("allows up to max requests, then rejects with 429 and Retry-After", async () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 2 });

  await limit(req, res, next);
  await limit(req, res, next);
  assert.equal(state.statusCode, 200, "first two requests pass");

  await limit(req, res, next);
  assert.equal(state.statusCode, 429, "third request is blocked");
  assert.ok(state.headers["retry-after"], "Retry-After header is set");
  assert.deepEqual(state.body, { error: "Too many requests — please slow down." });
});

test("uses a custom message when provided", async () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 1, message: "Slow down!" });
  await limit(req, res, next);
  await limit(req, res, next);
  assert.deepEqual(state.body, { error: "Slow down!" });
});

test("buckets independently per key", async () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({
    name: uniqueName(),
    windowMs: 60_000,
    max: 1,
    key: (r) => String(r.body.phoneNumber ?? ""),
  });

  req.body = { phoneNumber: "+15550000001" };
  await limit(req, res, next);
  assert.equal(state.statusCode, 200);

  // Same number again -> blocked.
  await limit(req, res, next);
  assert.equal(state.statusCode, 429);

  // A different number gets its own bucket.
  const second = harness();
  second.req.body = { phoneNumber: "+15550000002" };
  await limit(second.req, second.res, second.next);
  assert.equal(second.state.statusCode, 200);
});

test("key override falls back to the IP when it returns undefined", async () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 1, key: () => undefined });
  await limit(req, res, next);
  await limit(req, res, next);
  assert.equal(state.statusCode, 429);
});

test("uses the configured store (so instances can share one)", async () => {
  const seen: string[] = [];
  setRateLimitStore({
    async hit(bucket) {
      seen.push(bucket);
      return { allowed: false, retryAfterSeconds: 7 };
    },
  });
  try {
    const { req, res, state, next } = harness();
    await rateLimit({ name: "custom-store", windowMs: 1000, max: 1 })(req, res, next);
    assert.equal(state.statusCode, 429);
    assert.equal(state.headers["retry-after"], "7");
    assert.ok(seen[0]?.startsWith("custom-store:"), "bucket is namespaced by limit name");
  } finally {
    setRateLimitStore(memoryRateLimitStore);
  }
});

test("fails open when the store throws", async () => {
  setRateLimitStore({
    async hit() {
      throw new Error("db down");
    },
  });
  try {
    const { req, res, state, next } = harness();
    await rateLimit({ name: "boom", windowMs: 1000, max: 1 })(req, res, next);
    assert.equal(state.nextCalls, 1, "request is allowed through");
    assert.equal(state.statusCode, 200);
  } finally {
    setRateLimitStore(memoryRateLimitStore);
  }
});
