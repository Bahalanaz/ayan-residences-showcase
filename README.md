# Ayan Residences: Rental Management App

**A real-world product, built for a real client.** Ayan Residences is a
property rental business with apartments, short-stay condos and villas in the
**Philippines and the UAE**. This is not a tutorial or practice project: it
is the business's own software, designed, built and deployed by me as a
freelance full-stack developer (October 2026 to present).

One Flutter codebase serves two apps: an **admin app** for the owner and a
**tenant app** for the people renting.

**Status: in active development.** The live version runs on a private
Supabase backend and is being rolled out to the owner and tenants (Android
app, with an iPhone web app planned). New features are still being added.

> **This is a public showcase copy.** To protect the client and their tenants,
> it runs in **demo mode** with fictional sample data and no server. The live
> code, server settings and all real data stay in a private repository.

## Try it

```bash
flutter pub get
flutter run
```

Demo logins (sample data only):

| App | Username | Password |
|---|---|---|
| Admin | `1234` | `1234` |
| Tenant | `123` | `123` |

## What it does

**Admin app**
- Dashboard: payments to verify, occupancy, scheduled work, reports, cheques, complaints
- Properties and units (apartments per month, condos per night, villas per year)
- Tenant accounts, leases, renewals and move-outs with deposit settlement
- Automatic monthly rent charges from each lease (due-day rules, part payments, overdue tracking)
- Payment proof verification; villa post-dated cheques with bounced-cheque replacement
- Condo bookings with deposits and damage deductions
- Maintenance, damage reports and scheduling, with costs charged to tenants when they are at fault
- Finance: revenue, costs, taxes and net profit by month, year or custom range, in **two currencies (PHP and AED)**, with a PDF report comparing each period with the one before
- Announcements, private chat and an activity log

**Tenant app**
- Rent due, payment history and proof-of-payment upload
- Maintenance requests, complaints and modification requests with photos
- Lease, documents and **in-app e-signing**
- Notices, house rules and chat with management

## My role

Sole developer, working directly with the client: gathering requirements from
how the business actually runs (leases, rent collection, cheques, condo
bookings, repairs), designing the database and security rules, building both
apps, deploying the backend and testing with real users.

## Engineering highlights

- **Offline-first sync engine:** saves locally first, sends only what changed, retries failed saves and applies live updates (Supabase Realtime). Data loads never overlap, and deletions are guarded so a sync can never wipe records by mistake.
- **Security by the database:** PostgreSQL row-level security on every table. Each tenant can only reach their own records; the admin role is set by the server, never by the app.
- **Tamper-evident e-signing:** password re-check before signing, a server timestamp, SHA-256 fingerprints of the document before and after, and an audit page in the signed PDF. Supports signing on several pages.
- **Records are never lost:** money and history (paid rent, stays, done work, banked cheques) can't be deleted. Deleting a unit archives it, so Finance and the reports stay complete.
- **Push notifications:** a Supabase Edge Function (TypeScript) sends Firebase Cloud Messaging alerts for charges, payments, chat and maintenance.
- **Automated tests:** 46 widget and logic tests (`flutter test --dart-define=DEMO_DATA=true`).

## Tech stack

Flutter and Dart · Supabase (PostgreSQL, Auth, Storage, Realtime, Edge Functions) ·
Firebase Cloud Messaging · TypeScript (Deno) · PDF generation · Android and web (PWA)

Development tools: VS Code, Android Studio, Git, and Claude (AI coding assistant).

## Project layout

```
lib/
  admin/        admin app: screens and state
  screens/      tenant app screens
  state/        sync engine, backend, push notifications, signing
  widgets/      shared UI
supabase/
  migrations/   database tables, security rules and functions
  functions/    Edge Functions (push notifications, tenant logins)
test/           automated tests
```

## Connecting your own backend (optional)

1. Create a Supabase project and run the files in `supabase/migrations` in order.
2. Put your project URL and **publishable** key in `lib/config/supabase_config.dart`.
3. For push notifications, replace `android/app/google-services.json` with your own Firebase file.
4. Run with `flutter run --dart-define=DEMO_DATA=false`.

Never put a secret or service-role key in the app.
