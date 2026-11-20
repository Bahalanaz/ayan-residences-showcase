# Ayan Residences: database plan (for review)

Status: **draft, nothing created yet.** Approve or change it, then the tables
are built in Supabase (your Supabase project, Singapore).

---

## 1. Ground rules (apply to every table)

| Rule | What it means |
|---|---|
| **Every table is locked (RLS on)** | Nobody sees a row unless a rule allows it. Rules are written per table (section 4). |
| **Two kinds of logged-in user** | `admin` (the shared admin/landlady login) sees and changes everything. `tenant` sees only their own lease, money, reports and chat. |
| **The role is set by the server** | Stored in the account's `app_metadata` (users cannot edit it), never in anything the app or user can change. |
| **IDs** | Whole numbers that count up (`bigint`). Login accounts use Supabase's own user ID. |
| **Money** | `numeric(12,2)` (exact, never rounding errors) plus a `currency` of `PHP` or `AED`. Pesos and dirhams are never added together. |
| **Dates** | Days are `date`; moments (check-in, signed at, posted at) are `timestamptz` (time zone safe: PH and UAE differ by 4 hours). |
| **Fixed choices** | Values like status or type are `text` with an allowed list (e.g. status must be `pending`, `under_review` or `approved`). |
| **Nothing is wiped** | History is kept: past leases, past stays, former tenants, deleted-looking things are marked (`ended`, `cancelled`) instead of erased. |
| **Files are not in tables** | Photos and PDFs live in Supabase Storage; tables keep only the file's path. |
| **Every link is indexed** | Each column that points to another table gets an index, so lists stay fast. |
| **Tables are reachable only when granted** | "Expose new tables automatically" is off, so each table is opened to the app on purpose. |

---

## 2. Accounts and login

- Logins use Supabase Auth. The app keeps **username + password** as it does
  now; behind the scenes each username is stored as a private address
  (`<username>@accounts.ayan.app`, never emailed).
- **Only the admin creates tenant accounts**, through a small server function
  (it needs the secret key, which never goes in the app).
- **One admin account**, shared by admin and landlady (as agreed). Its role is
  `admin`.

### `profiles` (one row per login)
| Column | Type | Notes |
|---|---|---|
| id | uuid | Same as the Supabase login ID |
| role | text | `admin` or `tenant` (copied from the server-set role, for display) |
| username | text | unique |
| created_at | timestamptz | |

---

## 3. Tables

### A. Properties and units

**`properties`**: Ayan Tower B, Ayan Villas, Ayan Stays...
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| name | text | unique |
| created_at | timestamptz | |

**`units`**
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| property_id | bigint â†’ properties | |
| name | text | "Unit 402", "Villa 2", "Studio 3"; unique |
| type | text | `apartment`, `condo`, `villa` |
| bedrooms | smallint | 0 = studio |
| rate | numeric(12,2) | rent or nightly rate |
| rate_unit | text | `month`, `night` |
| currency | text | `PHP` or `AED` (villas: AED) |
| deposit_amount | numeric(12,2) | null = same as one rate |
| photo_path | text | Storage path, optional |
| created_at | timestamptz | |

*Status (vacant / reserved / occupied) and condition (ready / under repair /
maintenance / modification) are **worked out** from leases, bookings and
scheduled work, not stored, so they can never be wrong.*

**`unit_templates`**: saved settings for adding units quickly (name,
property, type, bedrooms, rate, rate_unit, photo_path).

### B. Tenants and leases

**`tenants`**
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| profile_id | uuid â†’ profiles | their login (unique) |
| full_name | text | |
| phone, email | text | |
| emergency_contact | text | |
| occupants | smallint | declared number of people |
| status | text | `active`, `moved_out` |
| created_at | timestamptz | |

**`leases`**: current, past and agreed-but-not-started leases in one place
(replaces "past leases" and "next lease").
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| tenant_id | bigint â†’ tenants | |
| unit_id | bigint â†’ units | |
| start_date, end_date | date | |
| rent | numeric(12,2) | |
| currency | text | |
| due_day | smallint | 1-31 (short months use their last day) |
| deposit | numeric(12,2) | security deposit held (0 for villas) |
| cheques_per_year | smallint | villas only, 1-4 |
| paid_until | date | the paid-through date |
| status | text | `scheduled`, `active`, `ended`, `cancelled` |
| contract_path | text | assigned contract PDF |
| signed_lease_path | text | photo of the signed lease |
| renewed_from | bigint â†’ leases | the lease this renews, if any |
| created_at | timestamptz | |

*Rule: one `active` lease per unit at a time.*

**`tenant_documents`**: Valid ID, clearances, Passport, Visa, EID, Ejari...
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| tenant_id | bigint â†’ tenants | |
| kind | text | e.g. `valid_id`, `passport`, `ejari` |
| file_path | text | Storage |
| state | text | `to_review`, `verified`, `rejected` |
| reject_reason | text | |
| uploaded_at, reviewed_at | timestamptz | |

**`lease_requests`**: renewal requests and move-out notices from tenants
(tenant_id, kind `renewal`/`move_out`, note, status `pending`/`approved`/`declined`, created_at).

**`move_outs`**: the record kept when someone leaves (lease_id, moved_out_on,
deduction, deduction_reason, deposit_note, owed_at_move_out, created_at).

### C. Money

**`charges`**: what a tenant owes (monthly rent, water bill, bounced cheque fee, repair charged to tenant...)
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| tenant_id | bigint â†’ tenants | |
| lease_id | bigint â†’ leases | null for a one-off charge |
| title | text | "November 2026 rent", "Repair: Broken cabinet" |
| kind | text | `rent`, `utility`, `repair`, `fee`, `other` |
| amount | numeric(12,2) | |
| paid_amount | numeric(12,2) | running total of part-payments |
| currency | text | |
| due_date | date | |
| period_month | date | for rent: the month it covers (stops duplicates) |
| status | text | `open`, `paid`, `cancelled` |
| created_at | timestamptz | |

*Rule: a lease can't have two rent charges for the same month.*

**`payments`**: money received (tenant proof, cash recorded by admin, online via Xendit, cleared cheque)
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| tenant_id | bigint â†’ tenants | |
| title | text | |
| amount | numeric(12,2) | |
| currency | text | |
| method | text | GCash, BDO transfer, Cash, Cheque, Online... |
| reference | text | |
| paid_on | date | |
| source | text | `tenant_proof`, `admin_recorded`, `online`, `cheque` |
| status | text | `submitted`, `verified`, `rejected` |
| reject_reason | text | |
| proof_path | text | screenshot in Storage |
| months, covers_from, covers_to | | for rent payments |
| gateway_ref | text | Xendit payment ID (unique) |
| verified_at | timestamptz | |
| created_at | timestamptz | |

**`payment_allocations`**: which charges a payment paid, and how much of each (makes part-payments exact)
(payment_id, charge_id, amount).

*Finance counts a payment as income only when `verified` (your rule).*

**`cheques`**: villa deposit and post-dated cheques
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| lease_id | bigint â†’ leases | |
| kind | text | `deposit`, `post_dated` |
| amount | numeric(12,2) | AED |
| cheque_date | date | |
| months | smallint | months of rent it pays |
| cheque_no, bank | text | |
| status | text | `held`, `deposited`, `cleared`, `bounced` |
| replaces_id | bigint â†’ cheques | the bounced cheque it replaces |
| photo_path | text | |
| photo_uploaded_at | timestamptz | |
| photo_checked | boolean | |
| reminded | boolean | |
| returned_on | date | handed back at move-out |
| created_at | timestamptz | |

**`pay_accounts`**: GCash / Maya / bank accounts tenants pay to (type, name, account_name, number, qr_path, sort_order).

**`taxes`**: name, percent, fixed_monthly, on_villas.

**`monthly_expenses`**: per unit (unit_id, name, amount, currency, since_month, until_month).

**`expense_templates`**: name, amount, unit_type (`apartment` or `condo`; each shows only for its type).

**`unit_costs`**: one-off condo operating costs (unit_id, title, amount, spent_on).

**`cost_types`**, **`charge_types`**: the dropdown lists the admin can extend (name).

### D. Condo stays (no tenant accounts)

**`bookings`**
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| unit_id | bigint â†’ units | |
| guest_name, phone | text | |
| guests | smallint | |
| check_in, check_out | timestamptz | |
| amount | numeric(12,2) | counted as income on check-in day (your rule) |
| deposit | numeric(12,2) | |
| deposit_returned_on | date | |
| status | text | `booked`, `cancelled` |
| created_at | timestamptz | |

*Rule: two bookings for the same unit can never overlap (enforced by the database).*

**`booking_deductions`**: amount taken off a guest's deposit (booking_id, amount, reason, deducted_on).

**`booking_files`**: guest ID and other files (booking_id, label, file_path, added_at).

### E. Work, reports and complaints

**`work_items`**: scheduled repair / maintenance / inspection / modification
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| unit_id | bigint â†’ units | null when for a whole property |
| property_id | bigint â†’ properties | set when for a whole property |
| kind | text | `repair`, `maintenance`, `inspection`, `modification` |
| title | text | |
| start_date, end_date | date | |
| time_label | text | "9:00 AM - 5:00 PM", "All day" |
| cost | numeric(12,2) | value of the work / damage |
| tenant_pays | boolean | |
| charge_id | bigint â†’ charges | the payment request sent to the tenant |
| report_id | bigint â†’ reports | the report it came from, if any |
| done | boolean | |
| notes | text | |
| created_at | timestamptz | |

**`reports`**: tenant reports and the landlady's manual condo reports
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| code | text | "TK-1082", "MR-1" (unique) |
| tenant_id | bigint â†’ tenants | null for a manual report |
| unit_id | bigint â†’ units | |
| type | text | `maintenance`, `damage`, `modification` |
| issue, description | text | |
| status | text | `pending`, `under_review`, `approved` |
| damage_kind | text | `accident`, `intentional` (damage only) |
| tenant_amount | numeric(12,2) | amount to pay by tenant |
| created_at | timestamptz | |

**`report_updates`**: progress notes the tenant sees (report_id, text, posted_at).

**`report_photos`**: (report_id, file_path, added_at).

**`complaints`**: (tenant_id, category, body, status `open`/`in_progress`/`resolved`, response, created_at).

### F. Messages, notices and signing

**`notices`**: announcements and automatic notices
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| kind | text | `emergency`, `schedule`, `repair`, `general` |
| title, body | text | |
| automatic | boolean | sent by the app (cheque cleared, reminders) |
| unit_types | text[] | who it went to, e.g. {apartment, villa} |
| created_at | timestamptz | |

**`notice_recipients`**: one row per tenant who received it (notice_id, tenant_id, read_at). Gives "read by 2 of 3".

**`house_rules`**: (title, body, sort_order).

**`chat_messages`**: one private thread per tenant
| Column | Type | Notes |
|---|---|---|
| id | uuid | made by the app (safe to resend) |
| tenant_id | bigint â†’ tenants | which thread |
| sender | text | `tenant`, `admin` |
| body | text | |
| image_path | text | |
| created_at | timestamptz | set by the server |

**`chat_reads`**: last time each side opened a thread (tenant_id, side, read_at).

**`documents_to_sign`**: signature requests and signed documents shown in the chat
| Column | Type | Notes |
|---|---|---|
| id | bigint | |
| tenant_id | bigint â†’ tenants | |
| message_id | uuid â†’ chat_messages | the chat card |
| title | text | |
| original_path | text | the PDF/photo as sent |
| original_hash | text | SHA-256 fingerprint |
| status | text | `awaiting`, `signed`, `accepted` |
| revision | smallint | times sent back |
| return_note | text | |
| signature_path | text | the drawn signature |
| signed_path | text | the signed PDF |
| signed_hash | text | fingerprint of the signed PDF (kept by the server) |
| signed_at | timestamptz | **server time** |
| signed_device | text | |
| accepted_at | timestamptz | after this the row is locked |

### G. System

**`activity_log`**: (id, actor uuid, action, detail, created_at). Written by the server; nobody can edit or delete it.

**`settings`**: one row: gateway fee %, bounced cheque fee, renewal notice days, rent charge lead days, latest app version + APK link (for "Update available").

**`alert_prefs`**: which dashboard alerts the admin wants (key, enabled).

**`push_tokens`**: phone notification tokens (profile_id, token, platform, updated_at).

---

## 4. Who can see and change what

| Data | Tenant | Admin |
|---|---|---|
| properties, units, house rules, pay accounts | read | full |
| their own profile / tenant record | read; edit phone, email, emergency contact, occupants | full |
| their own leases, charges, payments, cheques | read | full |
| payments | **add** a proof (status forced to `submitted`) | full |
| cheques | upload a photo only | full |
| tenant documents | upload / replace their own | review, verify, reject |
| reports | add and read their own; add photos | full |
| report updates | read their own | full |
| complaints, lease requests | add and read their own | full |
| notices | read the ones sent to them; mark read | full |
| chat | read and send in their own thread | full |
| documents to sign | read their own; sign while `awaiting` | send, accept, return |
| bookings, booking files, unit costs, expenses, taxes, settings, activity log, templates | **no access** | full (activity log: read only) |

Every rule is written with `(select auth.uid())` so it runs once per query,
and every column used in a rule is indexed.

---

## 5. File storage (all private, opened with short-lived links)

| Bucket | Holds | Who |
|---|---|---|
| `tenant-documents` | IDs, clearances, passports | owner tenant + admin |
| `payment-proofs` | payment screenshots | owner tenant + admin |
| `cheque-photos` | cheque photos | owner tenant + admin |
| `contracts` | contracts, signed leases, signed PDFs | owner tenant + admin |
| `chat-files` | chat photos, documents to sign, signatures | thread's tenant + admin |
| `report-photos` | report photos | report's tenant + admin |
| `guest-files` | condo guest IDs | admin only |
| `public-assets` | unit photos, payment QR codes | any logged-in user can view; admin uploads |

---

## 6. Work done by the server

**Small server functions** (they hold the secret keys):
- `create-tenant-account`: admin makes a login for a tenant.
- `sign-document`: stamps server time, fingerprints the signed PDF, locks it on acceptance.
- `xendit-create-payment` / `xendit-webhook`: online payments; a payment is recorded as verified only when Xendit confirms it.
- `send-push`: phone notifications for new notices, payment requests and reminders.

**Daily job (every morning, PH time)**:
create the month's rent charges Â· mark overdue charges Â· cheque reminders (3 days before) Â·
lease-end reminders (90 days) Â· start renewals whose date has come.

---

## 7. Questions for you

1. **Login names:** keep username + password for tenants (as now)? The alternative is logging in with their real email, which also allows "forgot password" by email.
2. **Data kept forever?** The plan never deletes (former tenants, past stays, old payments). Is that what the client wants?
3. **Monthly limits:** fine to stay on the free plan while building and switch to Pro (~$25/month, daily backups) before real tenants join?
