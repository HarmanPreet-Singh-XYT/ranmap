import { Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { limitFor, type PlanTierName } from "@/lib/data/plan";
import { getTrip, listTripExpenses } from "@/lib/data/trips";
import { Card, CardContent } from "@/components/ui/card";
import { deleteExpense } from "../../actions";
import { ExpenseForm } from "./_components/expense-form";
import {
  AddExpenseImages,
  RemoveExpenseImage,
} from "./_components/expense-media";

const MAX_THUMBS = 2;

function money(amount: number, currency: string): string {
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency,
    }).format(amount);
  } catch {
    return `${amount.toFixed(2)} ${currency}`;
  }
}

export default async function TripExpensesPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const [expenses, trip, auth, planRows] = await Promise.all([
    listTripExpenses(supabase, id),
    getTrip(supabase, id),
    supabase.auth.getUser(),
    supabase.rpc("my_plan"),
  ]);
  const currency = trip?.currency ?? "USD";
  const userId = auth.data.user?.id ?? "";
  const total = expenses.reduce((sum, e) => sum + Number(e.amount ?? 0), 0);

  // How many images this account may attach (0053). Display only — the DB
  // enforces it, and the action surfaces a refusal as a paywall.
  const plan = ((planRows.data ?? []) as { plan?: string }[])[0]?.plan ?? "free";
  const tier: PlanTierName =
    plan === "extreme" ? "extreme" : plan === "pro" ? "pro" : "free";
  const attachmentLimit = limitFor("attachments", tier);

  // Images live in the private `map-media` bucket, so each needs its own
  // short-lived link. Signed server-side, where the session lives.
  const signedUrls = new Map<string, string>();
  await Promise.all(
    expenses
      .flatMap((expense) => expense.attachments)
      .map(async (path) => {
        const { data } = await supabase.storage
          .from("map-media")
          .createSignedUrl(path, 60 * 60);
        if (data?.signedUrl) signedUrls.set(path, data.signedUrl);
      }),
  );

  return (
    <div className="space-y-4">
      <ExpenseForm
        tripId={id}
        currency={currency}
        userId={userId}
        limit={attachmentLimit}
      />

      <Card size="sm">
        <CardContent className="flex items-center justify-between">
          <span className="text-sm font-semibold text-slate-700">Total</span>
          <span className="font-display text-xl font-extrabold text-slate-900">
            {money(total, currency)}
          </span>
        </CardContent>
      </Card>

      {expenses.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            No expenses logged yet.
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {expenses.map((expense) => {
            const shown = expense.attachments.slice(0, MAX_THUMBS);
            const extra = expense.attachments.length - shown.length;
            // Only whoever logged the expense may change its images (the media
            // table's policies), so only they get the controls.
            const mine = expense.user_id === userId;
            return (
              <li key={expense.id}>
                <Card size="sm">
                  <CardContent className="flex items-center gap-3">
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">
                        {expense.category[0].toUpperCase() + expense.category.slice(1)}
                        {expense.note ? ` · ${expense.note}` : ""}
                      </p>
                      <p className="truncate text-xs text-muted-foreground">
                        {expense.logged_at
                          ? new Date(expense.logged_at).toLocaleDateString()
                          : ""}
                        {expense.fuel_liters ? ` · ${expense.fuel_liters} L` : ""}
                        {expense.place_name ? ` · ${expense.place_name}` : ""}
                      </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-1">
                      {shown.map((path) => {
                        const url = signedUrls.get(path);
                        if (!url) return null;
                        return (
                          <div key={path} className="relative">
                            <a
                              href={url}
                              target="_blank"
                              rel="noreferrer"
                              title="Receipt image"
                            >
                              {/* Signed URL from the private bucket; next/image
                                  would need a loader for it. */}
                              {/* eslint-disable-next-line @next/next/no-img-element */}
                              <img
                                src={url}
                                alt=""
                                className="size-10 rounded-md border border-[#E6E3DA] object-cover"
                              />
                            </a>
                            {mine && (
                              <RemoveExpenseImage
                                expenseId={expense.id}
                                tripId={id}
                                storagePath={path}
                              />
                            )}
                          </div>
                        );
                      })}
                      {extra > 0 && (
                        <span className="text-xs font-semibold text-muted-foreground">
                          +{extra}
                        </span>
                      )}
                    </div>
                    <span className="shrink-0 font-semibold">
                      {money(Number(expense.amount), expense.currency || currency)}
                    </span>
                    <form action={deleteExpense}>
                      <input type="hidden" name="trip_id" value={id} />
                      <input type="hidden" name="expense_id" value={expense.id} />
                      <button
                        type="submit"
                        aria-label="Delete expense"
                        className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </form>
                    {mine && (
                      <AddExpenseImages
                        expenseId={expense.id}
                        tripId={id}
                        userId={userId}
                        limit={attachmentLimit}
                        attached={expense.attachments.length}
                      />
                    )}
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
