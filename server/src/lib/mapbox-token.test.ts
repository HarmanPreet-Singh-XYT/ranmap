import assert from "node:assert/strict";
import { test } from "node:test";
import { createMapboxTokenVendor } from "./mapbox-token.js";

const TTL_MS = 55 * 60 * 1000;

/** A minimal fetch Response stand-in for the tokens under test. */
function fakeResponse(body: unknown, ok = true, status = 200) {
  return {
    ok,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

function mintOk(counter: { calls: number }, ttlMs = TTL_MS) {
  return (async () => {
    counter.calls += 1;
    return fakeResponse({
      token: `tk.${counter.calls}`,
      expires: new Date(Date.now() + ttlMs).toISOString(),
    });
  }) as unknown as typeof fetch;
}

test("mints a token and reuses the cached one until it nears expiry", async () => {
  const counter = { calls: 0 };
  const vendor = createMapboxTokenVendor({
    username: "acct",
    authorizingToken: "sk.test",
    fetchImpl: mintOk(counter),
  });

  const now = Date.now();
  const first = await vendor.getTemporaryToken(now);
  const second = await vendor.getTemporaryToken(now + 60_000);

  assert.equal(counter.calls, 1);
  assert.equal(first.token, second.token);
  assert.equal(first.token, "tk.1");
});

test("re-mints once the cached token is within the refresh margin", async () => {
  const counter = { calls: 0 };
  const vendor = createMapboxTokenVendor({
    username: "acct",
    authorizingToken: "sk.test",
    fetchImpl: mintOk(counter),
  });

  const now = Date.now();
  await vendor.getTemporaryToken(now);
  // 51 minutes in: only ~4 minutes of the 55-minute token remain.
  const refreshed = await vendor.getTemporaryToken(now + 51 * 60_000);

  assert.equal(counter.calls, 2);
  assert.equal(refreshed.token, "tk.2");
});

test("shares one in-flight mint across concurrent callers", async () => {
  const counter = { calls: 0 };
  const vendor = createMapboxTokenVendor({
    username: "acct",
    authorizingToken: "sk.test",
    fetchImpl: (async () => {
      counter.calls += 1;
      await new Promise((resolve) => setTimeout(resolve, 5));
      return fakeResponse({
        token: "tk.shared",
        expires: new Date(Date.now() + TTL_MS).toISOString(),
      });
    }) as unknown as typeof fetch,
  });

  const [a, b] = await Promise.all([vendor.getTemporaryToken(), vendor.getTemporaryToken()]);

  assert.equal(counter.calls, 1);
  assert.equal(a.token, b.token);
  assert.equal(a.token, "tk.shared");
});

test("throws when Mapbox rejects the mint", async () => {
  const vendor = createMapboxTokenVendor({
    username: "acct",
    authorizingToken: "sk.test",
    fetchImpl: (async () => fakeResponse({ message: "Not authorized" }, false, 401)) as unknown as typeof fetch,
  });

  await assert.rejects(() => vendor.getTemporaryToken(), /Mapbox token mint failed \(401\)/);
});

test("throws when a successful mint still carries no token", async () => {
  const vendor = createMapboxTokenVendor({
    username: "acct",
    authorizingToken: "sk.test",
    fetchImpl: (async () =>
      fakeResponse({ expires: new Date(Date.now() + TTL_MS).toISOString() })) as unknown as typeof fetch,
  });

  await assert.rejects(() => vendor.getTemporaryToken(), /returned no token/);
});
