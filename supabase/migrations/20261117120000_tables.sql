-- Ayan Residences: tables (part 1 of 3). See docs/database_plan.md.
-- Conventions: bigint identity ids, text + check for fixed choices,
-- numeric(12,2) for money with a PHP/AED currency, date for days and
-- timestamptz for moments, every foreign key indexed.

create extension if not exists btree_gist with schema extensions;

-- ===================================================== properties & units

create table public.properties (
  id bigint generated always as identity primary key,
  name text not null unique,
  created_at timestamptz not null default now()
);

create table public.units (
  id bigint generated always as identity primary key,
  property_id bigint not null references public.properties (id),
  name text not null unique,
  type text not null check (type in ('apartment', 'condo', 'villa')),
  bedrooms smallint not null default 1 check (bedrooms >= 0),
  rate numeric(12,2) not null check (rate >= 0),
  rate_unit text not null check (rate_unit in ('month', 'night')),
  currency text not null check (currency in ('PHP', 'AED')),
  deposit_amount numeric(12,2) check (deposit_amount >= 0),
  photo_path text,
  created_at timestamptz not null default now()
);
create index units_property_id_idx on public.units (property_id);

create table public.unit_templates (
  id bigint generated always as identity primary key,
  name text not null unique,
  property_id bigint references public.properties (id),
  type text not null check (type in ('apartment', 'condo', 'villa')),
  bedrooms smallint not null default 1 check (bedrooms >= 0),
  rate numeric(12,2) check (rate >= 0),
  rate_unit text not null check (rate_unit in ('month', 'night')),
  photo_path text,
  created_at timestamptz not null default now()
);
create index unit_templates_property_id_idx on public.unit_templates (property_id);

-- ===================================================== accounts & tenants

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'tenant')),
  username text not null unique,
  created_at timestamptz not null default now()
);

create table public.tenants (
  id bigint generated always as identity primary key,
  profile_id uuid unique references public.profiles (id),
  full_name text not null,
  phone text not null default '',
  email text not null default '',
  emergency_contact text not null default '',
  occupants smallint not null default 1 check (occupants >= 1),
  status text not null default 'active' check (status in ('active', 'moved_out')),
  created_at timestamptz not null default now()
);

create table public.leases (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  unit_id bigint not null references public.units (id),
  start_date date not null,
  end_date date not null,
  rent numeric(12,2) not null check (rent >= 0),
  currency text not null check (currency in ('PHP', 'AED')),
  due_day smallint not null default 5 check (due_day between 1 and 31),
  deposit numeric(12,2) not null default 0 check (deposit >= 0),
  cheques_per_year smallint check (cheques_per_year between 1 and 4),
  paid_until date,
  status text not null default 'active'
    check (status in ('scheduled', 'active', 'ended', 'cancelled')),
  contract_name text,
  contract_path text,
  signed_lease_path text,
  renewed_from bigint references public.leases (id),
  created_at timestamptz not null default now(),
  check (end_date > start_date)
);
create index leases_tenant_id_idx on public.leases (tenant_id);
create index leases_unit_id_idx on public.leases (unit_id);
create index leases_renewed_from_idx on public.leases (renewed_from);
-- One lease in force per unit at a time.
create unique index leases_one_active_per_unit on public.leases (unit_id) where status = 'active';

create table public.tenant_documents (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  kind text not null,
  file_name text not null,
  file_path text not null,
  state text not null default 'to_review' check (state in ('to_review', 'verified', 'rejected')),
  reject_reason text,
  uploaded_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index tenant_documents_tenant_id_idx on public.tenant_documents (tenant_id);
-- The latest file per document kind replaces the earlier one.
create unique index tenant_documents_one_per_kind on public.tenant_documents (tenant_id, kind);

create table public.lease_requests (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  kind text not null check (kind in ('renewal', 'move_out', 'other')),
  details text not null default '',
  note text not null default '',
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now()
);
create index lease_requests_tenant_id_idx on public.lease_requests (tenant_id);

create table public.move_outs (
  id bigint generated always as identity primary key,
  lease_id bigint not null unique references public.leases (id),
  moved_out_on date not null,
  deduction numeric(12,2) not null default 0 check (deduction >= 0),
  deduction_reason text not null default '',
  deposit_note text not null default '',
  owed_at_move_out numeric(12,2) not null default 0,
  created_at timestamptz not null default now()
);

-- ===================================================== money

create table public.charges (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  lease_id bigint references public.leases (id),
  title text not null,
  kind text not null check (kind in ('rent', 'utility', 'repair', 'fee', 'other')),
  amount numeric(12,2) not null check (amount > 0),
  paid_amount numeric(12,2) not null default 0 check (paid_amount >= 0),
  currency text not null check (currency in ('PHP', 'AED')),
  due_date date not null,
  period_month date,
  status text not null default 'open' check (status in ('open', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  check (paid_amount <= amount)
);
create index charges_tenant_id_idx on public.charges (tenant_id);
create index charges_lease_id_idx on public.charges (lease_id);
create index charges_open_due_idx on public.charges (due_date) where status = 'open';
-- Never two rent charges for the same lease and month.
create unique index charges_one_rent_per_month on public.charges (lease_id, period_month)
  where kind = 'rent' and status <> 'cancelled';

create table public.payments (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  title text not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null check (currency in ('PHP', 'AED')),
  method text not null,
  reference text not null default '',
  paid_on date not null,
  source text not null check (source in ('tenant_proof', 'admin_recorded', 'online', 'cheque')),
  status text not null default 'submitted' check (status in ('submitted', 'verified', 'rejected')),
  reject_reason text,
  proof_path text,
  months smallint check (months >= 1),
  covers_from date,
  covers_to date,
  gateway_ref text unique,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index payments_tenant_id_idx on public.payments (tenant_id);
create index payments_submitted_idx on public.payments (created_at) where status = 'submitted';

create table public.payment_allocations (
  id bigint generated always as identity primary key,
  payment_id bigint not null references public.payments (id),
  charge_id bigint not null references public.charges (id),
  amount numeric(12,2) not null check (amount > 0),
  unique (payment_id, charge_id)
);
create index payment_allocations_charge_id_idx on public.payment_allocations (charge_id);

create table public.cheques (
  id bigint generated always as identity primary key,
  lease_id bigint not null references public.leases (id),
  kind text not null check (kind in ('deposit', 'post_dated')),
  amount numeric(12,2) not null check (amount > 0),
  cheque_date date not null,
  months smallint not null default 0 check (months >= 0),
  cheque_no text not null default '',
  bank text not null default '',
  status text not null default 'held' check (status in ('held', 'deposited', 'cleared', 'bounced')),
  replaces_id bigint references public.cheques (id),
  photo_path text,
  photo_uploaded_at timestamptz,
  photo_checked boolean not null default false,
  reminded boolean not null default false,
  returned_on date,
  created_at timestamptz not null default now()
);
create index cheques_lease_id_idx on public.cheques (lease_id);
create index cheques_replaces_id_idx on public.cheques (replaces_id);

create table public.pay_accounts (
  id bigint generated always as identity primary key,
  type text not null check (type in ('GCash', 'Maya', 'Bank', 'Other')),
  name text not null,
  account_name text not null,
  number text not null,
  qr_path text,
  sort_order smallint not null default 0
);

create table public.taxes (
  id bigint generated always as identity primary key,
  name text not null,
  percent numeric(5,2) not null default 0 check (percent between 0 and 100),
  fixed_monthly numeric(12,2) not null default 0 check (fixed_monthly >= 0),
  on_villas boolean not null default false
);

create table public.monthly_expenses (
  id bigint generated always as identity primary key,
  unit_id bigint not null references public.units (id),
  name text not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null check (currency in ('PHP', 'AED')),
  since_month date not null,
  until_month date,
  created_at timestamptz not null default now()
);
create index monthly_expenses_unit_id_idx on public.monthly_expenses (unit_id);

create table public.expense_templates (
  id bigint generated always as identity primary key,
  name text not null,
  amount numeric(12,2) not null check (amount > 0),
  unit_type text not null check (unit_type in ('apartment', 'condo')),
  unique (unit_type, name)
);

create table public.unit_costs (
  id bigint generated always as identity primary key,
  unit_id bigint not null references public.units (id),
  title text not null,
  amount numeric(12,2) not null check (amount > 0),
  spent_on date not null,
  created_at timestamptz not null default now()
);
create index unit_costs_unit_id_idx on public.unit_costs (unit_id);

create table public.cost_types (
  id bigint generated always as identity primary key,
  name text not null unique
);

create table public.charge_types (
  id bigint generated always as identity primary key,
  name text not null unique
);

-- ===================================================== condo stays

create table public.bookings (
  id bigint generated always as identity primary key,
  unit_id bigint not null references public.units (id),
  guest_name text not null,
  phone text not null default '',
  guests smallint not null default 1 check (guests >= 1),
  check_in timestamptz not null,
  check_out timestamptz not null,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  deposit numeric(12,2) not null default 0 check (deposit >= 0),
  deposit_returned_on date,
  status text not null default 'booked' check (status in ('booked', 'cancelled')),
  created_at timestamptz not null default now(),
  check (check_out > check_in),
  -- Two stays in the same unit can never overlap.
  constraint bookings_no_overlap exclude using gist (
    unit_id with =,
    tstzrange(check_in, check_out) with &&
  ) where (status = 'booked')
);
create index bookings_unit_id_idx on public.bookings (unit_id);

create table public.booking_deductions (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings (id),
  amount numeric(12,2) not null check (amount > 0),
  reason text not null default '',
  deducted_on date not null,
  created_at timestamptz not null default now()
);
create index booking_deductions_booking_id_idx on public.booking_deductions (booking_id);

create table public.booking_files (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.bookings (id),
  label text not null,
  file_name text not null,
  file_path text not null,
  added_at timestamptz not null default now()
);
create index booking_files_booking_id_idx on public.booking_files (booking_id);

-- ===================================================== work, reports, complaints

create table public.reports (
  id bigint generated always as identity primary key,
  code text not null unique,
  tenant_id bigint references public.tenants (id),
  unit_id bigint not null references public.units (id),
  type text not null check (type in ('maintenance', 'damage', 'modification')),
  issue text not null,
  description text not null,
  status text not null default 'pending' check (status in ('pending', 'under_review', 'approved')),
  damage_kind text check (damage_kind in ('accident', 'intentional')),
  tenant_amount numeric(12,2) not null default 0 check (tenant_amount >= 0),
  created_at timestamptz not null default now()
);
create index reports_tenant_id_idx on public.reports (tenant_id);
create index reports_unit_id_idx on public.reports (unit_id);

create table public.report_updates (
  id bigint generated always as identity primary key,
  report_id bigint not null references public.reports (id),
  body text not null,
  posted_at timestamptz not null default now()
);
create index report_updates_report_id_idx on public.report_updates (report_id);

create table public.report_photos (
  id bigint generated always as identity primary key,
  report_id bigint not null references public.reports (id),
  file_path text not null,
  added_at timestamptz not null default now()
);
create index report_photos_report_id_idx on public.report_photos (report_id);

create table public.work_items (
  id bigint generated always as identity primary key,
  unit_id bigint references public.units (id),
  property_id bigint references public.properties (id),
  kind text not null check (kind in ('repair', 'maintenance', 'inspection', 'modification')),
  title text not null,
  start_date date not null,
  end_date date not null,
  time_label text not null default 'All day',
  cost numeric(12,2) not null default 0 check (cost >= 0),
  tenant_pays boolean not null default false,
  charge_id bigint references public.charges (id),
  report_id bigint references public.reports (id),
  done boolean not null default false,
  notes text not null default '',
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  -- A job is for one unit or for a whole property, never both or neither.
  check ((unit_id is null) <> (property_id is null))
);
create index work_items_unit_id_idx on public.work_items (unit_id);
create index work_items_property_id_idx on public.work_items (property_id);
create index work_items_charge_id_idx on public.work_items (charge_id);
create index work_items_report_id_idx on public.work_items (report_id);

create table public.complaints (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  category text not null,
  body text not null,
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  response text,
  created_at timestamptz not null default now()
);
create index complaints_tenant_id_idx on public.complaints (tenant_id);

-- ===================================================== notices, chat, signing

create table public.notices (
  id bigint generated always as identity primary key,
  kind text not null default 'general' check (kind in ('emergency', 'schedule', 'repair', 'general')),
  title text not null,
  body text not null,
  automatic boolean not null default false,
  unit_types text[],
  created_at timestamptz not null default now()
);

create table public.notice_recipients (
  notice_id bigint not null references public.notices (id),
  tenant_id bigint not null references public.tenants (id),
  read_at timestamptz,
  primary key (notice_id, tenant_id)
);
create index notice_recipients_tenant_id_idx on public.notice_recipients (tenant_id);

create table public.house_rules (
  id bigint generated always as identity primary key,
  title text not null,
  body text not null,
  sort_order smallint not null default 0
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id bigint not null references public.tenants (id),
  sender text not null check (sender in ('tenant', 'admin')),
  body text,
  image_path text,
  created_at timestamptz not null default now(),
  check (body is not null or image_path is not null)
);
create index chat_messages_thread_idx on public.chat_messages (tenant_id, created_at);

create table public.chat_reads (
  tenant_id bigint not null references public.tenants (id),
  side text not null check (side in ('tenant', 'admin')),
  read_at timestamptz not null default now(),
  primary key (tenant_id, side)
);

create table public.documents_to_sign (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  message_id uuid references public.chat_messages (id),
  title text not null,
  original_name text,
  original_path text,
  original_hash text,
  status text not null default 'awaiting' check (status in ('awaiting', 'signed', 'accepted')),
  revision smallint not null default 0,
  return_note text,
  signature_path text,
  signed_path text,
  signed_hash text,
  signed_at timestamptz,
  signed_device text,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index documents_to_sign_tenant_id_idx on public.documents_to_sign (tenant_id);
create index documents_to_sign_message_id_idx on public.documents_to_sign (message_id);

-- ===================================================== system

create table public.activity_log (
  id bigint generated always as identity primary key,
  actor uuid references public.profiles (id),
  action text not null,
  detail text not null default '',
  created_at timestamptz not null default now()
);
create index activity_log_created_at_idx on public.activity_log (created_at desc);
create index activity_log_actor_idx on public.activity_log (actor);

-- A single row of app-wide settings.
create table public.settings (
  id boolean primary key default true check (id),
  gateway_fee_percent numeric(5,2) not null default 2.5,
  bounced_cheque_fee numeric(12,2) not null default 500,
  renewal_notice_days smallint not null default 90,
  rent_charge_lead_days smallint not null default 10,
  latest_app_version text,
  latest_apk_url text
);
insert into public.settings default values;

create table public.alert_prefs (
  key text primary key,
  enabled boolean not null default true
);

create table public.push_tokens (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index push_tokens_profile_id_idx on public.push_tokens (profile_id);
