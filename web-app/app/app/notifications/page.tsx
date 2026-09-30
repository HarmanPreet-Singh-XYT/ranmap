import type { Metadata } from "next";
import { Bell, Check, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { listNotifications } from "@/lib/data/notifications";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  deleteNotification,
  markAllNotificationsRead,
  markNotificationRead,
} from "./actions";

export const metadata: Metadata = { title: "Notifications" };

function timeAgo(iso: string): string {
  const diff = Date.now() - Date.parse(iso);
  const mins = Math.round(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return new Date(iso).toLocaleDateString();
}

export default async function NotificationsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const notifications = await listNotifications(supabase);
  const unread = notifications.filter((n) => !n.read_at).length;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="font-display text-2xl font-bold tracking-tight text-slate-900">
          Notifications
        </h1>
        {unread > 0 && (
          <form action={markAllNotificationsRead}>
            <Button type="submit" variant="outline" size="sm">
              <Check aria-hidden />
              Mark all read
            </Button>
          </form>
        )}
      </div>

      {notifications.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <Bell className="size-8 text-muted-foreground" aria-hidden />
            <p className="font-medium">Nothing here yet</p>
            <p className="max-w-sm text-sm text-muted-foreground">
              Invites, messages, and convoy alerts show up here.
            </p>
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-2">
          {notifications.map((notification) => (
            <li key={notification.id}>
              <Card
                size="sm"
                className={notification.read_at ? "" : "ring-emerald-600/30"}
              >
                <CardContent className="flex items-start gap-3">
                  <span
                    className={`mt-1.5 size-2 shrink-0 rounded-full ${
                      notification.read_at ? "bg-transparent" : "bg-emerald-600"
                    }`}
                    aria-hidden
                  />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{notification.title}</p>
                    {notification.body && (
                      <p className="text-sm text-muted-foreground">
                        {notification.body}
                      </p>
                    )}
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      {timeAgo(notification.created_at)}
                    </p>
                  </div>
                  <div className="flex shrink-0 items-center gap-1">
                    {!notification.read_at && (
                      <form action={markNotificationRead}>
                        <input type="hidden" name="id" value={notification.id} />
                        <Button type="submit" size="sm" variant="ghost">
                          Read
                        </Button>
                      </form>
                    )}
                    <form action={deleteNotification}>
                      <input type="hidden" name="id" value={notification.id} />
                      <button
                        type="submit"
                        aria-label="Delete notification"
                        className="flex size-7 items-center justify-center rounded-md text-slate-400 hover:bg-red-50 hover:text-red-700"
                      >
                        <Trash2 className="size-4" aria-hidden />
                      </button>
                    </form>
                  </div>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
