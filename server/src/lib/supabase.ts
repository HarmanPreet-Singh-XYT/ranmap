import { createClient } from "@supabase/supabase-js";
import { env } from "./env.js";

// Admin client built with the Supabase secret key: bypasses RLS. Only ever
// used after a request has been authenticated (see requireAuth) and only for
// writes scoped to that user's own id — never trust a user_id passed in a
// request body.
export const supabaseAdmin = createClient(env.supabaseUrl, env.supabaseSecretKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
