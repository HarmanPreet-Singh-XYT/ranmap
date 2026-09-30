import type { Metadata } from "next";
import Link from "next/link";
import { ArrowLeft, FileText, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listDocuments } from "@/lib/data/documents";
import { Card, CardContent } from "@/components/ui/card";
import { deleteDocument } from "./actions";
import { DocumentUpload } from "./upload-form";

export const metadata: Metadata = { title: "Documents" };

export default async function DocumentsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const documents = await listDocuments(supabase, user.id);

  return (
    <div className="mx-auto w-full max-w-3xl space-y-6">
      <Link
        href="/app/profile"
        className="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 hover:text-emerald-700"
      >
        <ArrowLeft className="size-3.5" aria-hidden />
        Profile
      </Link>
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Documents
        </h1>
        <p className="text-sm text-muted-foreground">
          Your private wallet — license, insurance, tickets. Only you can see these.
        </p>
      </div>

      <DocumentUpload userId={user.id} />

      {documents.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <FileText className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">No documents yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Add the paperwork you want on hand during a trip.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {documents.map((doc) => (
            <li key={doc.id}>
              <Card size="sm">
                <CardContent className="flex items-center gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-emerald-50 text-emerald-700">
                    <FileText className="size-4" aria-hidden />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{doc.name}</p>
                    <p className="truncate text-xs capitalize text-muted-foreground">
                      {doc.kind}
                      {doc.expires_at
                        ? ` · expires ${new Date(doc.expires_at).toLocaleDateString()}`
                        : ""}
                    </p>
                  </div>
                  {doc.url && (
                    <a
                      href={doc.url}
                      target="_blank"
                      rel="noreferrer"
                      className="shrink-0 text-xs font-semibold text-emerald-700 hover:text-emerald-800"
                    >
                      Open
                    </a>
                  )}
                  <form action={deleteDocument}>
                    <input type="hidden" name="id" value={doc.id} />
                    <input type="hidden" name="path" value={doc.storage_path} />
                    <button
                      type="submit"
                      aria-label={`Delete ${doc.name}`}
                      className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                    >
                      <Trash2 className="size-4" aria-hidden />
                    </button>
                  </form>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
