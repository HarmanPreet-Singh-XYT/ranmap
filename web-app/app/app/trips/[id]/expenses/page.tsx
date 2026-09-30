import { Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { getTrip, listTripExpenses } from "@/lib/data/trips";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { addExpense, deleteExpense } from "../../actions";

const CATEGORIES = ["fuel", "food", "toll", "lodging", "other"] as const;

const fieldClass =
  "h-9 w-full rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40";
const labelClass = "text-xs font-semibold text-slate-700";

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
  const [expenses, trip] = await Promise.all([
    listTripExpenses(supabase, id),
    getTrip(supabase, id),
  ]);
  const currency = trip?.currency ?? "USD";
  const total = expenses.reduce((sum, e) => sum + Number(e.amount ?? 0), 0);

  return (
    <div className="space-y-4">
      <Card size="sm">
        <CardContent>
          <form action={addExpense} className="space-y-4">
            <input type="hidden" name="trip_id" value={id} />
            <input type="hidden" name="currency" value={currency} />
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <label className={labelClass} htmlFor="category">
                  Category
                </label>
                <select id="category" name="category" defaultValue="fuel" className={fieldClass}>
                  {CATEGORIES.map((c) => (
                    <option key={c} value={c}>
                      {c[0].toUpperCase() + c.slice(1)}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1.5">
                <label className={labelClass} htmlFor="amount">
                  Amount ({currency})
                </label>
                <input
                  id="amount"
                  name="amount"
                  type="number"
                  min="0"
                  step="0.01"
                  required
                  className={fieldClass}
                />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <label className={labelClass} htmlFor="fuel_liters">
                  Fuel (L)
                </label>
                <input id="fuel_liters" name="fuel_liters" type="number" min="0" step="0.1" className={fieldClass} />
              </div>
              <div className="space-y-1.5">
                <label className={labelClass} htmlFor="note">
                  Note
                </label>
                <input id="note" name="note" maxLength={500} className={fieldClass} />
              </div>
            </div>
            <Button type="submit" size="sm">
              Add expense
            </Button>
          </form>
        </CardContent>
      </Card>

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
          {expenses.map((expense) => (
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
                    </p>
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
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
