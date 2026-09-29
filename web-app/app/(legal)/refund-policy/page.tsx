import type { Metadata } from "next";
import Content from "@/content/legal/refund-policy.mdx";
import { LegalArticle } from "../_components/legal-article";

export const metadata: Metadata = {
  title: "Refund Policy",
  description: "How refunds work for Ranmap Pro and Extreme subscriptions.",
};

export default function RefundPolicyPage() {
  return (
    <LegalArticle title="Refund Policy" lastUpdated="September 28, 2026">
      <Content />
    </LegalArticle>
  );
}
