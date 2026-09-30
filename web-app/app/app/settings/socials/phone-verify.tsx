"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

/**
 * Two-step phone verification via Twilio (through the authenticated backend
 * proxy). On success the server writes phone_number + phone_verified, which the
 * page re-reads after a refresh.
 */
export function PhoneVerify() {
  const router = useRouter();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [stage, setStage] = useState<"phone" | "code">("phone");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function post(path: string, body: unknown): Promise<{ ok: boolean; error?: string }> {
    try {
      const res = await fetch(`/api/ranmap/phone/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = (await res.json().catch(() => ({}))) as { error?: string };
      return { ok: res.ok, error: json.error };
    } catch {
      return { ok: false, error: "Couldn't reach the server." };
    }
  }

  async function send() {
    setBusy(true);
    setError(null);
    const result = await post("send-code", { phoneNumber: phone.trim() });
    if (result.ok) setStage("code");
    else setError(result.error ?? "Couldn't send the code.");
    setBusy(false);
  }

  async function check() {
    setBusy(true);
    setError(null);
    const result = await post("check-code", { phoneNumber: phone.trim(), code: code.trim() });
    if (result.ok) router.refresh();
    else setError(result.error ?? "That code didn't work.");
    setBusy(false);
  }

  return (
    <div className="space-y-3">
      {stage === "phone" ? (
        <>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+1 555 123 4567"
            className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
          />
          <p className="text-xs text-muted-foreground">
            Use international format (E.164), e.g. +14155551234.
          </p>
          <Button type="button" size="sm" onClick={send} disabled={busy || phone.trim().length < 8}>
            {busy ? "Sending…" : "Send code"}
          </Button>
        </>
      ) : (
        <>
          <input
            inputMode="numeric"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            placeholder="6-digit code"
            className="h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
          />
          <div className="flex gap-2">
            <Button type="button" size="sm" onClick={check} disabled={busy || code.trim().length < 4}>
              {busy ? "Verifying…" : "Verify"}
            </Button>
            <Button type="button" size="sm" variant="ghost" onClick={() => setStage("phone")}>
              Change number
            </Button>
          </div>
        </>
      )}
      {error && <p className="text-xs text-red-700">{error}</p>}
    </div>
  );
}
