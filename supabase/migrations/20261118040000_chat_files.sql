-- Chat: a PDF file can be sent (e.g. a contract to read), kept in the
-- chat-files storage folder of that tenant.

alter table public.chat_messages add column if not exists file_path text;
alter table public.chat_messages add column if not exists file_name text;
