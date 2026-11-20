-- Deleting a unit in the app archives it instead of erasing it: it leaves
-- the lists, but its payments, stays, reports and costs keep pointing to it
-- and still count in Finance and the PDF reports.

alter table public.units add column if not exists archived_at timestamptz;
