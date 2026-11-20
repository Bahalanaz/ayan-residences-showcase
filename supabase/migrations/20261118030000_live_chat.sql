-- Live chat: new messages and signing updates are pushed to the phones the
-- moment they are saved. Each phone still only receives the rows the
-- security rules let it read (a tenant: their own thread).

alter publication supabase_realtime add table public.chat_messages, public.documents_to_sign;
