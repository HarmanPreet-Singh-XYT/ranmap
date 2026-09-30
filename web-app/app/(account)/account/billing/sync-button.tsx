"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

type Status = "idle" | "loading" | "done" | "error";

/**
 * Re-reads the caller's subscription from RevenueCat (via the backend) and
 * refreshes the page. Exists because the web only sees `profiles.plan`, which
 * is written by the RevenueCat webhook — a purchase that never reached us (e.g.
 * one attributed to an anonymous RevenueCat id) leaves the web stuck on Free.
 */
export function SyncPlanButton() {
  const router = useRouter();
  const [status, setStatus] = useState<Status>("idle");
  const [message, setMessage] = useState<string | null>(null);

  async function sync() {
    setStatus("loading");
    setMessage(null);
    try {
      const res = await fetch("/api/ranmap/billing/sync", { method: "POST" });
      const body = (await res.json().catch(() => ({}))) as {
        plan?: string;
        found?: boolean;
        error?: string;
      };
      if (!res.ok) {
        setStatus("error");
        setMessage(body.error ?? "Couldn't check your subscription.");
        return;
      }
      setStatus("done");
      if (body.plan && body.plan !== "free") {
        setMessage("Found an active subscription — refreshing…");
        router.refresh();
      } else if (body.found === false) {
        setMessage(
          "RevenueCat has no subscription under this account yet. Open the Ranmap app, make sure you're signed in, then try again.",
        );
      } else {
        setMessage("Your account has no active subscription.");
      }
    } catch {
      setStatus("error");
      setMessage("Couldn't reach the server. Please try again.");
    }
  }

  return (
    <div className="space-y-3">
      <Button
        type="button"
        variant="outline"
        onClick={sync}
        disabled={status === "loading"}
      >
        {status === "loading" ? "Checking…" : "Already subscribed? Sync purchase"}
      </Button>
      {message && (
        <Alert variant={status === "error" ? "destructive" : "default"}>
          <AlertDescription>{message}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
