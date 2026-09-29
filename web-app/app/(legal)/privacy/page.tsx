import type { Metadata } from "next";
import Content from "@/content/legal/privacy.mdx";
import { LegalArticle } from "../_components/legal-article";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Ranmap collects, uses, and protects your data.",
};

export default function PrivacyPage() {
  return (
    <LegalArticle title="Privacy Policy" lastUpdated="September 28, 2026">
      <Content />
    </LegalArticle>
  );
}
