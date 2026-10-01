import { redirect } from "next/navigation";

/** Billing now lives in the app shell. */
export default function BillingRedirect() {
  redirect("/app/profile/billing");
}
