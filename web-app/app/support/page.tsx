import type { Metadata } from "next";
import { SupportContent } from "./support-content";

export const metadata: Metadata = {
  title: "Support · Convoy Setup Guides & Help",
  description:
    "Find answers on convoy setup, live voice, offline maps, stops, expenses and billing — or message the Ranmap support team directly.",
  alternates: { canonical: "/support" },
  openGraph: {
    title: "Support · Convoy Setup Guides & Help",
    description:
      "Find answers on convoy setup, live voice, offline maps, stops, expenses and billing — or message the Ranmap support team directly.",
    url: "/support",
  },
};

export default function SupportPage() {
  return <SupportContent />;
}
