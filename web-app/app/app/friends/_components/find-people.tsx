"use client";

import { useState } from "react";
import { Loader2, Search } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { blockUser, reportUser, sendFriendRequest } from "../actions";

interface Result {
  id: string;
  username: string;
  display_name: string | null;
}

export function FindPeople() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Result[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searched, setSearched] = useState(false);

  async function search() {
    const q = query.trim();
    if (q.length < 2) {
      setError("Type at least 2 characters.");
      return;
    }
    setLoading(true);
    setError(null);
    setSearched(true);
    try {
      const supabase = createClient();
      const { data, error: rpcError } = await supabase.rpc("search_profiles", {
        p_query: q,
      });
      if (rpcError) throw rpcError;
      setResults((data ?? []) as Result[]);
      if ((data ?? []).length === 0) setError("No one found with that name.");
    } catch {
      setError("Search is unavailable right now.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card size="sm">
      <CardContent className="space-y-3">
        <div className="flex gap-2">
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                void search();
              }
            }}
            placeholder="Find people by username"
            className="h-9 flex-1 rounded-lg border border-[#E6E3DA] bg-white px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
          />
          <Button type="button" variant="outline" size="sm" onClick={search} disabled={loading}>
            {loading ? <Loader2 className="animate-spin" aria-hidden /> : <Search aria-hidden />}
            Search
          </Button>
        </div>

        {error && <p className="text-xs text-red-700">{error}</p>}

        {searched && results.length === 0 && !error && (
          <p className="text-xs text-muted-foreground">No matches.</p>
        )}

        {results.length > 0 && (
          <ul className="divide-y divide-[#E6E3DA] rounded-lg border border-[#E6E3DA]">
            {results.map((person) => (
              <li
                key={person.id}
                className="flex items-center justify-between gap-3 px-3 py-2"
              >
                <span className="min-w-0">
                  <span className="block truncate text-sm font-medium">
                    {person.display_name || person.username}
                  </span>
                  <span className="block truncate text-xs text-muted-foreground">
                    @{person.username}
                  </span>
                </span>
                <div className="flex shrink-0 gap-1.5">
                  <form action={sendFriendRequest}>
                    <input type="hidden" name="user_id" value={person.id} />
                    <Button type="submit" size="sm">
                      Add
                    </Button>
                  </form>
                  <form action={blockUser}>
                    <input type="hidden" name="user_id" value={person.id} />
                    <Button type="submit" size="sm" variant="ghost">
                      Block
                    </Button>
                  </form>
                  <form action={reportUser} className="flex items-center gap-1">
                    <input type="hidden" name="user_id" value={person.id} />
                    <select
                      name="reason"
                      defaultValue="other"
                      aria-label="Report reason"
                      className="h-7 rounded-lg border border-[#E6E3DA] bg-white px-1.5 text-xs outline-none focus-visible:ring-2 focus-visible:ring-emerald-600/40"
                    >
                      <option value="spam">Spam</option>
                      <option value="harassment">Harassment</option>
                      <option value="explicit">Explicit</option>
                      <option value="violence">Violence</option>
                      <option value="other">Other</option>
                    </select>
                    <Button type="submit" size="sm" variant="ghost">
                      Report
                    </Button>
                  </form>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
