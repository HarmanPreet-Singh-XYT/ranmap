/**
 * Mints short-lived Mapbox "temporary" tokens (`tk.…`) for the mobile app, so
 * the app ships no long-lived Mapbox credential.
 *
 * Why: a public `pk.` token baked into an app is extractable, and rotating it
 * would break every installed client until users update. A temporary token is
 * read-only, expires within an hour (Mapbox's hard cap), and needs no rotation —
 * if it leaks it simply dies, and rotating the underlying secret becomes a
 * server-only change.
 *
 * Reference:
 * https://docs.mapbox.com/api/accounts/tokens/#create-a-temporary-token
 */

/** A temporary token and when it expires (ISO-8601), as the client receives it. */
export interface TemporaryMapboxToken {
  token: string;
  expiresAt: string;
}

// The rendering scopes the app's map needs — and nothing more:
//   styles:read   load the style JSON
//   fonts:read    Mapbox fonts
//   styles:tiles  style tiles, including the terrain DEM raster source
const RENDER_SCOPES = ["styles:read", "fonts:read", "styles:tiles"];

// Mapbox caps temporary tokens at one hour; refresh a little earlier so a token
// can't lapse while a client is still using it.
const TOKEN_TTL_MS = 55 * 60 * 1000;
const REFRESH_MARGIN_MS = 5 * 60 * 1000;

export interface MapboxTokenVendorOptions {
  /** The Mapbox account username the token is minted under. */
  username: string;
  /** A secret token authorised to mint tokens (needs `tokens:write` + scopes). */
  authorizingToken: string;
  /** Injectable for tests. */
  fetchImpl?: typeof fetch;
}

export interface MapboxTokenVendor {
  /** A cached token, minted fresh when the cache is missing or near expiry. */
  getTemporaryToken(now?: number): Promise<TemporaryMapboxToken>;
  /** Clears the cache (tests). */
  reset(): void;
}

export function createMapboxTokenVendor(options: MapboxTokenVendorOptions): MapboxTokenVendor {
  const fetchImpl = options.fetchImpl ?? fetch;
  let cached: TemporaryMapboxToken | null = null;
  let inFlight: Promise<TemporaryMapboxToken> | null = null;

  async function mint(now: number): Promise<TemporaryMapboxToken> {
    const expiresAt = new Date(now + TOKEN_TTL_MS).toISOString();
    const url =
      `https://api.mapbox.com/tokens/v2/${encodeURIComponent(options.username)}` +
      `?access_token=${encodeURIComponent(options.authorizingToken)}`;
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ expires: expiresAt, scopes: RENDER_SCOPES }),
    });
    if (!response.ok) {
      const detail = (await response.text().catch(() => "")).slice(0, 200);
      throw new Error(`Mapbox token mint failed (${response.status}): ${detail}`);
    }
    const body = (await response.json()) as { token?: unknown; expires?: unknown };
    if (typeof body.token !== "string" || body.token === "") {
      throw new Error("Mapbox token mint returned no token");
    }
    cached = {
      token: body.token,
      expiresAt: typeof body.expires === "string" ? body.expires : expiresAt,
    };
    return cached;
  }

  return {
    getTemporaryToken(now: number = Date.now()): Promise<TemporaryMapboxToken> {
      if (cached && Date.parse(cached.expiresAt) - now > REFRESH_MARGIN_MS) {
        return Promise.resolve(cached);
      }
      // Share one mint across concurrent callers so a burst of app launches
      // can't multiply Tokens API requests (Mapbox caps them per account).
      inFlight ??= mint(now).finally(() => {
        inFlight = null;
      });
      return inFlight;
    },
    reset(): void {
      cached = null;
      inFlight = null;
    },
  };
}
