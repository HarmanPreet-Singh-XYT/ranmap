"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Upload } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import {
  documentMimeOf,
  DOCUMENT_TOO_LARGE_MESSAGE,
  isAllowedDocument,
  MAX_DOCUMENT_BYTES,
  UNSUPPORTED_DOCUMENT_MESSAGE,
} from "@/lib/data/document";
import { classifyPlanMessage } from "@/lib/data/plan";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PaywallNotice } from "../_components/paywall-notice";

const KINDS = ["license", "insurance", "ticket", "registration", "other"] as const;

export function DocumentUpload({ userId }: { userId: string }) {
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [name, setName] = useState("");
  const [kind, setKind] = useState<string>("other");
  const [expires, setExpires] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [premium, setPremium] = useState(false);

  async function upload() {
    if (!file || !name.trim() || busy) return;
    // The bucket enforces these (0055); checking here gives a specific message
    // instead of a generic Storage rejection.
    if (!isAllowedDocument(file)) {
      setError(UNSUPPORTED_DOCUMENT_MESSAGE);
      setPremium(false);
      return;
    }
    if (file.size > MAX_DOCUMENT_BYTES) {
      setError(DOCUMENT_TOO_LARGE_MESSAGE);
      setPremium(false);
      return;
    }
    setBusy(true);
    setError(null);
    setPremium(false);
    try {
      const supabase = createClient();
      const ext = (file.name.split(".").pop() ?? "pdf").toLowerCase().replace(/[^a-z0-9]/g, "") || "pdf";
      const path = `${userId}/${Date.now()}_${crypto.randomUUID().slice(0, 8)}.${ext}`;

      const { error: upErr } = await supabase.storage
        .from("documents")
        // Never `application/octet-stream`: the bucket refuses it, and it tells
        // the browser nothing about what the file is.
        .upload(path, file, { contentType: documentMimeOf(file) });
      if (upErr) throw upErr;

      const { error: insErr } = await supabase.from("user_documents").insert({
        user_id: userId,
        name: name.trim().slice(0, 80),
        kind,
        storage_path: path,
        expires_at: expires ? new Date(expires).toISOString() : null,
      });
      if (insErr) throw insErr;

      setFile(null);
      setName("");
      setExpires("");
      router.refresh();
    } catch (err) {
      // Free accounts are capped at 1 document (DB trigger) — surface the
      // "Ranmap Pro required" message with an upgrade path.
      const info = classifyPlanMessage(err instanceof Error ? err.message : "");
      setError(info.message || "Couldn't upload that document. Please try again.");
      setPremium(info.premium);
    } finally {
      setBusy(false);
    }
  }

  const field =
    "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";

  return (
    <Card size="sm">
      <CardContent className="space-y-4">
        <input
          type="file"
          accept="image/*,application/pdf"
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null;
            setFile(f);
            if (f && !name) setName(f.name.replace(/\.[^.]+$/, ""));
          }}
          className="block w-full text-sm text-slate-600 file:mr-3 file:rounded-full file:border-0 file:bg-emerald-700 file:px-4 file:py-1.5 file:text-xs file:font-bold file:uppercase file:tracking-wide file:text-white hover:file:bg-emerald-800"
        />
        <div className="grid gap-4 sm:grid-cols-3">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={80}
            placeholder="Document name"
            className={field}
          />
          <select value={kind} onChange={(e) => setKind(e.target.value)} className={`${field} capitalize`}>
            {KINDS.map((k) => (
              <option key={k} value={k}>
                {k}
              </option>
            ))}
          </select>
          <input
            type="date"
            value={expires}
            onChange={(e) => setExpires(e.target.value)}
            aria-label="Expiry date"
            className={field}
          />
        </div>
        {error && <PaywallNotice message={error} premium={premium} />}
        <Button type="button" size="sm" disabled={!file || !name.trim() || busy} onClick={upload}>
          {busy ? <Loader2 className="animate-spin" aria-hidden /> : <Upload aria-hidden />}
          {busy ? "Uploading…" : "Add document"}
        </Button>
      </CardContent>
    </Card>
  );
}
