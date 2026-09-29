import type { Metadata } from "next";
import Content from "@/content/legal/terms.mdx";
import { LegalArticle } from "../_components/legal-article";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The terms that govern your use of Ranmap.",
};

export default function TermsPage() {
  return (
    <LegalArticle title="Terms of Service" lastUpdated="September 28, 2026">
      <Content />
    </LegalArticle>
  );
}
