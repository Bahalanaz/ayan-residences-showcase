-- Live updates for everything: when the admin changes a lease, rent, notice
-- or verifies a payment (or a tenant sends something), the other phones
-- reload it within a few seconds. Each phone only hears about rows the
-- security rules let it read.

alter publication supabase_realtime add table
  public.units,
  public.tenants,
  public.leases,
  public.move_outs,
  public.tenant_documents,
  public.lease_requests,
  public.charges,
  public.payments,
  public.cheques,
  public.pay_accounts,
  public.bookings,
  public.reports,
  public.report_updates,
  public.work_items,
  public.complaints,
  public.notices,
  public.notice_recipients,
  public.house_rules,
  public.tenant_messages,
  public.settings;
