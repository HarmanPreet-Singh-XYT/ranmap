/**
 * Validates a `?next=` redirect target: only same-origin absolute paths are
 * allowed, so the login flow can't be turned into an open redirect.
 */
export function safeNextPath(next: string | null | undefined): string | null {
  if (!next) return null;
  // Must be an absolute path on this origin — reject "//host" and schemes.
  if (!next.startsWith("/") || next.startsWith("//")) return null;
  if (next.includes("://")) return null;
  return next;
}
