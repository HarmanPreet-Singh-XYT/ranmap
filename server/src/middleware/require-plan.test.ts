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

test("requirePro gates place_photos for a free user with its own feature id", async () => {
  const { req, res, state, next } = harness();
  await requirePro("place_photos", async () => false, "Place photos are a Ranmap Pro feature.")(
    req,
    res,
    next,
  );
  assert.equal(state.nextCalls, 0);
  assert.equal(state.statusCode, 402);
  assert.deepEqual(state.body, {
    error: "Place photos are a Ranmap Pro feature.",
    code: "premium_required",
    feature: "place_photos",
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
    async () => "free",
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

test("requireProOrTrial meters a Pro user against proMax, then 429s (not a paywall)", async () => {
  const { req, res, state, next } = harness("pro-user-1");
  let calls = 0;
  const mw = requireProOrTrial(
    "maps_search",
    {
      max: 1,
      proMax: 2,
      windowMs: 60_000,
      message: "free capped",
      proMessage: "plan capped",
    },
    async () => "pro",
    async (_u, _f, limit) => {
      assert.equal(limit, 2, "Pro is metered against proMax, not the free max");
      calls += 1;
      return calls <= 2;
    },
  );

  await mw(req, res, next);
  await mw(req, res, next);
  assert.equal(state.nextCalls, 2, "both Pro requests under the ceiling pass");

  await mw(req, res, next);
  assert.equal(state.nextCalls, 2, "the third is blocked");
  assert.equal(state.statusCode, 429, "a Pro user gets 429, not the 402 paywall");
  assert.deepEqual(state.body, {
    error: "plan capped",
    code: "limit_reached",
    feature: "maps_search",
  });
});

test("requireProOrTrial forwards a metering failure to next", async () => {
  const { req, res, state, next } = harness("user-err");
  const mw = requireProOrTrial(
    "ai_assistant",
    { max: 1, windowMs: 60_000, message: "capped" },
    async () => "free",
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
    async () => "free",
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
    async () => "free",
    async () => 100,
  )(req, res, next);

  assert.equal(state.nextCalls, 0);
  assert.equal(state.statusCode, 402);
});

test("requireWithinAllowance applies the proMax ceiling for a Pro user", async () => {
  const opts = {
    max: 100,
    proMax: 1_000,
    windowMs: 60_000,
    message: "free out",
    proMessage: "plan out",
  };

  const under = harness();
  await requireWithinAllowance("ai_assistant", opts, async () => "pro", async () => 999)(
    under.req,
    under.res,
    under.next,
  );
  assert.equal(under.state.nextCalls, 1, "under proMax, a Pro user passes");

  const atCap = harness();
  await requireWithinAllowance("ai_assistant", opts, async () => "pro", async () => 1_000)(
    atCap.req,
    atCap.res,
    atCap.next,
  );
  assert.equal(atCap.state.nextCalls, 0);
  assert.equal(atCap.state.statusCode, 429, "a Pro user gets 429, not the 402 paywall");
});

test("requireWithinAllowance uses extremeMax for an Extreme user", async () => {
  const opts = {
    max: 100,
    proMax: 1_000,
    extremeMax: 5_000,
    windowMs: 60_000,
    message: "free out",
    proMessage: "pro out",
    extremeMessage: "extreme out",
  };

  const under = harness();
  await requireWithinAllowance("ai_assistant", opts, async () => "extreme", async () => 4_999)(
    under.req,
    under.res,
    under.next,
  );
  assert.equal(under.state.nextCalls, 1, "under extremeMax, an Extreme user passes");

  const atCap = harness();
  await requireWithinAllowance("ai_assistant", opts, async () => "extreme", async () => 5_000)(
    atCap.req,
    atCap.res,
    atCap.next,
  );
  assert.equal(atCap.state.nextCalls, 0);
  assert.equal(atCap.state.statusCode, 429);
  assert.deepEqual(atCap.state.body, {
    error: "extreme out",
    code: "limit_reached",
    feature: "ai_assistant",
  });
});

test("requireWithinAllowance forwards a usage-read failure to next", async () => {
  const { req, res, state, next } = harness("user-err");
  await requireWithinAllowance(
    "ai_assistant",
    allowanceOpts,
    async () => "free",
    async () => {
      throw new Error("db down");
    },
  )(req, res, next);

  assert.equal(state.nextCalls, 1);
  assert.equal(state.statusCode, 200, "not a paywall");
});
