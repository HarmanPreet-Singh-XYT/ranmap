-- 0049_conversation_reads.sql
--
-- Read receipts for direct messages: one row per (conversation, member) holding
-- when that member last opened the thread. The sender's client shows a message
-- as "read" (blue double tick) once the other member's last_read_at passes its
-- created_at. Written only through mark_conversation_read().
--
-- Safe to re-run.

create table if not exists public.conversation_reads (
  conversation_id uuid not null
    references public.direct_conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

alter table public.conversation_reads enable row level security;

drop policy if exists "conversation_reads_select_member" on public.conversation_reads;
create policy "conversation_reads_select_member" on public.conversation_reads
  for select using (public.is_conversation_member(conversation_id, auth.uid()));

revoke insert, update, delete on public.conversation_reads from anon, authenticated;

create or replace function public.mark_conversation_read(p_conv uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_conversation_member(p_conv, auth.uid()) then
    raise exception 'not a member of this conversation' using errcode = '42501';
  end if;
  insert into public.conversation_reads (conversation_id, user_id, last_read_at)
  values (p_conv, auth.uid(), now())
  on conflict (conversation_id, user_id)
  do update set last_read_at = excluded.last_read_at;
end;
$$;

revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'conversation_reads'
  ) then
    alter publication supabase_realtime add table public.conversation_reads;
  end if;
end;
$$;
