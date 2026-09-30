-- 0045_group_avatar_photo.sql
--
-- Lets a group carry an uploaded photo, not just a generated Multiavatar seed.
-- An uploaded photo is stored as `custom:<storage path>`, which is far longer
-- than the 64-char cap 0026 put on groups.avatar_id (that cap assumed bare
-- seeds only), so no group photo could ever be saved. Raise the cap to match
-- profiles.avatar_id (512, see 0035) and relax update_group's validation to
-- the same bound.
--
-- Safe to re-run: the old length check is dropped before the wider one is added,
-- and update_group is `create or replace`.

alter table public.groups drop constraint if exists groups_avatar_len_chk;
alter table public.groups
  add constraint groups_avatar_len_chk
  check (avatar_id is null or char_length(avatar_id) between 1 and 512) not valid;
alter table public.groups validate constraint groups_avatar_len_chk;

create or replace function public.update_group(
  p_group uuid,
  p_name text,
  p_description text default null,
  p_avatar_id text default null
)
returns public.groups
language plpgsql security definer set search_path = public as $$
declare
  v_group public.groups;
begin
  if not public.is_group_admin(p_group, auth.uid()) then
    raise exception 'only an admin can edit this group';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'name is required';
  end if;
  if char_length(btrim(p_name)) > 60 then
    raise exception 'name is too long';
  end if;
  if p_description is not null and char_length(p_description) > 200 then
    raise exception 'description is too long';
  end if;
  if p_avatar_id is not null
     and (char_length(p_avatar_id) < 1 or char_length(p_avatar_id) > 512) then
    raise exception 'invalid avatar';
  end if;

  update public.groups set
    name = btrim(p_name),
    description = p_description,
    avatar_id = coalesce(p_avatar_id, avatar_id)
  where id = p_group
  returning * into v_group;

  return v_group;
end;
$$;
