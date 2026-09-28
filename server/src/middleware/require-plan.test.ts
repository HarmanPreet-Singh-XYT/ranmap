import assert from "node:assert/strict";
import { test } from "node:test";
import type { NextFunction, Request, Response } from "express";
import { requirePro, requireProOrTrial, requireWithinAllowance } from "./require-plan.js";

/** Minimal Express req/res/next for exercising middleware directly. */
function harness(userId = "user-1") {
  const state = {
    statusCode: 200,
    body: undefined as unknown,
    nextCalls: 0,
    error: undefined as unknown,
  };
  const req = { userId } as unknown as Request;
  const res = {
    status(code: number) {
      state.statusCode = code;
      return res;
    },
    json(body: unknown) {
      state.body = body;
      return res;
    },
  } as unknown as Response;
  const next = ((err?: unknown) => {
    state.nextCalls += 1;
    state.error = err;
  }) as NextFunction;
  return { req, res, state, next };
}

test("requirePro lets an active Pro user through", async () => {
  const { req, res, state, next } = harness();
  await requirePro("voice", async () => true)(req, res, next);
  assert.equal(state.nextCalls, 1);
  assert.equal(state.statusCode, 200);
});

test("requirePro returns a 402 paywall body for a free user", async () => {
  const { req, res, state, next } = harness();
  await requirePro("voice", async () => false)(req, res, next);
  assert.equal(state.nextCalls, 0);
  assert.equal(state.statusCode, 402);
  assert.deepEqual(state.body, {
    error: "This is a Ranmap Pro feature.",
    code: "premium_required",
    feature: "voice",
  });
});

test("requirePro forwards a lookup failure to next rather than paywalling", async () => {
  const { req, res, state, next } = harness();
  const boom = new Error("db down");
  await requirePro("ai_assistant", async () => {
    throw boom;
  })(req, res, next);
  assert.equal(state.nextCalls, 1);
  assert.equal(state.error, boom);
  assert.equal(state.statusCode, 200);
});

test("requireProOrTrial meters a free user then paywalls, with the custom message", async () => {
  const { req, res, state, next } = harness("trial-user-1");
  let used = 0;
  const consume = async () => {
    used += 1;
    return used <= 2;
  };
  const mw = requireProOrTrial(
    "ai_assistant",
    { max: 2, windowMs: 60_000, message: "out of free messages" },
    async () => false,
    consume,
  );

  await mw(req, res, next);
  await mw(req, res, next);
  assert.equal(state.nextCalls, 2, "both free messages pass");

  await mw(req, res, next);
  assert.equal(state.nextCalls, 2, "third is blocked");
  assert.equal(state.statusCode, 402);
  assert.deepEqual(state.body, {
    error: "out of free messages",
    code: "premium_required",
    feature: "ai_assistant",
  });
});

test("requireProOrTrial never meters a Pro user", async () => {
  const { req, res, state, next } = harness("pro-user-1");
  let metered = false;
  const mw = requireProOrTrial(
    "maps_search",
    { max: 1, windowMs: 60_000, message: "capped" },
    async () => true,
    async () => {
      metered = true;
      return true;
    },
  );

  for (let i = 0; i < 5; i++) await mw(req, res, next);
  assert.equal(state.nextCalls, 5);
  assert.equal(state.statusCode, 200);
  assert.equal(metered, false, "the meter is never consulted for a Pro user");
});

test("requireProOrTrial forwards a metering failure to next", async () => {
  const { req, res, state, next } = harness("user-err");
  const mw = requireProOrTrial(
    "ai_assistant",
    { max: 1, windowMs: 60_000, message: "capped" },
    async () => false,
    async () => {
      throw new Error("db down");
    },
  );

  await mw(req, res, next);
  assert.equal(state.nextCalls, 1);
  assert.equal(state.statusCode, 200, "not a paywall");
});

// --- requireWithinAllowance (token metering: check up front, record later) ---

const allowanceOpts = { max: 100, windowMs: 60_000, message: "out of tokens" };

test("requireWithinAllowance lets an under-limit user through and reads usage", async () => {
  const { req, res, state, next } = harness();
  let reads = 0;
  await requireWithinAllowance(
    "ai_assistant",
    allowanceOpts,
    async () => false,
    async () => {
      reads += 1;
      return 99;
    },
  )(req, res, next);

  assert.equal(state.nextCalls, 1);
  assert.equal(reads, 1, "usage is read to decide the cap");
});

test("requireWithinAllowance paywalls at the limit", async () => {
  const { req, res, state, next } = harness();
  await requireWithinAllowance(
    "ai_assistant",
    allowanceOpts,
    async () => false,
    async () => 100,
  )(req, res, next);

  assert.equal(state.nextCalls, 0);
  assert.equal(state.statusCode, 402);
});

test("requireWithinAllowance lets Pro through without reading usage", async () => {
  const { req, res, state, next } = harness();
  let reads = 0;
  await requireWithinAllowance(
    "ai_assistant",
    allowanceOpts,
    async () => true,
    async () => {
      reads += 1;
      return 999;
    },
  )(req, res, next);

  assert.equal(state.nextCalls, 1);
  assert.equal(reads, 0, "a Pro user's usage is never consulted");
});

test("requireWithinAllowance forwards a usage-read failure to next", async () => {
  const { req, res, state, next } = harness("user-err");
  await requireWithinAllowance(
    "ai_assistant",
    allowanceOpts,
    async () => false,
    async () => {
      throw new Error("db down");
    },
  )(req, res, next);

  assert.equal(state.nextCalls, 1);
  assert.equal(state.statusCode, 200, "not a paywall");
});
