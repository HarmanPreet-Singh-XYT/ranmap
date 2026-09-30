"use client";

import { useState } from "react";
import { Check, Share2 } from "lucide-react";
import { Button } from "@/components/ui/button";

/** Copies a text recap of the trip to the clipboard. */
export function CopySummary({ summary }: { summary: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(summary);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard can be blocked (insecure context / permissions).
    }
  }

  return (
    <Button type="button" variant="outline" size="sm" onClick={copy}>
      {copied ? <Check aria-hidden /> : <Share2 aria-hidden />}
      {copied ? "Copied" : "Copy recap"}
    </Button>
  );
}
