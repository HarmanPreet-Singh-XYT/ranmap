-- Tool receipts for the AI assistant.
--
-- The assistant executes real actions server-side (save a place, create or
-- schedule a trip, invite a friend, add a stop). Persist exactly what ran and
-- its result, so the chat can show a truthful receipt — rather than the client
-- guessing from the reply text.
alter table public.ai_messages
  add column if not exists tools jsonb not null default '[]'::jsonb;
