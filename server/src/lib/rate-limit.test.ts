import assert from "node:assert/strict";
import { test } from "node:test";
import type { NextFunction, Request, Response } from "express";
import { rateLimit } from "./rate-limit.js";

/** Builds a minimal Express req/res pair for exercising middleware directly. */
function harness() {
  const state = {
    statusCode: 200,
    headers: {} as Record<string, string>,
    body: undefined as unknown,
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
  return { req, res, state, next: (() => {}) as NextFunction };
}

/** A unique bucket name per test so the shared in-memory store can't bleed. */
let seq = 0;
const uniqueName = () => `test-${++seq}-${Math.random().toString(36).slice(2)}`;

test("allows up to max requests, then rejects with 429 and Retry-After", () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 2 });

  limit(req, res, next);
  limit(req, res, next);
  assert.equal(state.statusCode, 200, "first two requests pass");

  limit(req, res, next);
  assert.equal(state.statusCode, 429, "third request is blocked");
  assert.ok(state.headers["retry-after"], "Retry-After header is set");
  assert.deepEqual(state.body, { error: "Too many requests — please slow down." });
});

test("uses a custom message when provided", () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 1, message: "Slow down!" });
  limit(req, res, next);
  limit(req, res, next);
  assert.deepEqual(state.body, { error: "Slow down!" });
});

test("buckets independently per key", () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({
    name: uniqueName(),
    windowMs: 60_000,
    max: 1,
    key: (r) => String(r.body.phoneNumber ?? ""),
  });

  req.body = { phoneNumber: "+15550000001" };
  limit(req, res, next);
  assert.equal(state.statusCode, 200);

  // Same number again -> blocked.
  limit(req, res, next);
  assert.equal(state.statusCode, 429);

  // A different number gets its own bucket.
  const second = harness();
  second.req.body = { phoneNumber: "+15550000002" };
  limit(second.req, second.res, second.next);
  assert.equal(second.state.statusCode, 200);
});

test("key override falls back to the IP when it returns undefined", () => {
  const { req, res, state, next } = harness();
  const limit = rateLimit({ name: uniqueName(), windowMs: 60_000, max: 1, key: () => undefined });
  limit(req, res, next);
  limit(req, res, next);
  assert.equal(state.statusCode, 429);
});
