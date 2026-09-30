-- 0041_map_posts_owner_select.sql
--
-- Let the owner read their own map posts, so `INSERT ... RETURNING` can return
-- a just-inserted row.
--
-- Why this is needed: `map_posts_select_visible` uses
-- `public.can_view_map_post(id, auth.uid())`, which re-queries `map_posts` by
-- the row's id. Within a single `INSERT ... RETURNING` the new row is not
-- visible to that subquery (same command, same snapshot), so the SELECT policy
-- rejects the row the INSERT policy just accepted. PostgreSQL reports it as
-- `42501 new row violates row-level security policy for table "map_posts"`, and
-- pinning a photo — `MapPostRepository.createPost`'s `.insert(...).select(...)`
-- — fails even though the insert itself is allowed.
--
-- RLS SELECT policies are OR'd, so an owner policy that reads the row's own
-- column (no subquery) satisfies the RETURNING check. It does not widen what
-- anyone can read: the owner could already select their own posts via
-- `can_view_map_post`'s `p.user_id = p_user` branch.
--
-- Safe to re-run.

drop policy if exists "map_posts_select_own" on public.map_posts;
create policy "map_posts_select_own" on public.map_posts
  for select using (user_id = auth.uid());
