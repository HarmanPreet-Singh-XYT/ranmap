-- Ranmap migration 0005: phone number verification
--
-- profiles.phone_number was freely editable with no verification — anyone
-- could claim any number. Adds phone_verified, writable only by the
-- service role (ranmap-server, after a successful Twilio Verify check), and
-- resets it automatically whenever phone_number changes so a verified
-- number can't be silently swapped for an unverified one from the client.
--
-- Safe to re-run.

alter table public.profiles add column if not exists phone_verified boolean not null default false;

-- The client may edit these profile columns directly, but never
-- phone_verified — only ranmap-server, using the service role (which bypasses
-- grants entirely), may set that after a successful Twilio Verify check.
--
-- NB: a column-level `revoke update (phone_verified)` is NOT enough here,
-- because Supabase's default leaves a *table-level* UPDATE grant on
-- `profiles`, and a table-level privilege covers every column regardless of
-- column-level revokes. So we drop the table-level grant and re-grant only
-- the columns a client is allowed to write.
revoke update on public.profiles from anon, authenticated;
grant update (username, display_name, avatar_id, vehicle_type, phone_number, socials)
  on public.profiles to anon, authenticated;

-- Only reset phone_verified when the *client* (authenticated/anon role,
-- via PostgREST) changes phone_number. The service role is exempt because
-- ranmap-server sets phone_number and phone_verified=true together in one
-- write after a successful Twilio Verify check.
create or replace function public.reset_phone_verified_on_change()
returns trigger language plpgsql as $$
begin
  if new.phone_number is distinct from old.phone_number
     and auth.role() <> 'service_role' then
    new.phone_verified := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reset_phone_verified on public.profiles;
create trigger trg_reset_phone_verified
  before update on public.profiles
  for each row
  execute function public.reset_phone_verified_on_change();

-- Surface phone_verified alongside the other private fields (it isn't in
-- the public select-column grant, same reasoning as phone_number/socials).
-- `create or replace` cannot change a function's OUT columns, so drop the
-- 2-column version created in 0002 first.
drop function if exists public.my_private_profile();
create or replace function public.my_private_profile()
returns table (phone_number text, socials jsonb, phone_verified boolean)
language sql stable security definer set search_path = public as $$
  select p.phone_number, p.socials, p.phone_verified from public.profiles p where p.id = auth.uid();
$$;

grant execute on function public.my_private_profile() to authenticated;
