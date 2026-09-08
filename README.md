# ZenSched Short-Term-Rental Turnover Reference Kit

A copy-pasteable setup for a solo STR cleaner or a 2–10 person turnover company that cleans Airbnb / VRBO units for many hosts and wants an AI assistant to load each week's checkouts, dispatch same-day turnovers, verify by GPS that the cleaner was at the unit, collect a photo Turnover Report (guest-ready proof, damage, left items, restock, linen counts), pay cleaners per turnover or per hour, and invoice hosts. ZenSched handles the live schedule, the cleaner's phone app, GPS check-ins at the unit, the photo report, and timesheets. A small local database on your computer holds your hosts, units, door codes, cleaner roster, the week's turnovers, restock lists, invoices, and pay runs.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("here's this week's checkouts", "dispatch", "is Palm 12B ready?", "restock list", "invoice Marisol", "pay run") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What ZenSched does and does not do for turnovers — read this first

**What this kit is:** a way for a turnover business to get GPS-verified, timestamped, photo-backed proof of every clean, keep hosts' door codes on the business's own computer, and turn those records into host invoices and cleaner pay with an AI assistant doing the dispatching and clerical work.

**What it is not:**

- **ZenSched does not sync with Airbnb, VRBO, Hospitable, Turno, Guesty, or any calendar.** It does not know about bookings or guests. You (or the AI, from a list you paste) load the week's checkouts and check-in times; the kit turns them into cleaning windows and shifts. If a guest extends or leaves early, you tell the AI and it moves the shift. There is no iCal import.
- **There is no host portal.** Hosts do not log in anywhere. Proof of a clean is the Turnover Report with photos; the AI gives you the photo links and you forward them by text or email. The kit does not build a client-facing page.
- **No payments.** Invoices are plain text you paste into an email. The kit does not charge cards, collect deposits, or pay cleaners; it tells you what is owed and records that you paid.
- **Not a marketplace.** You bring your own cleaners; ZenSched sends them the app invite and the shifts.

If you need calendar sync or a host portal today, this kit is not it yet. If you run on a spreadsheet and a group chat and want same-day dispatch with proof, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (one per unit, with GPS coordinates; the check-in radius is a policy setting)
- Workers (cleaners with the mobile app)
- Events (one "Turnovers" job per unit, renewed every 60 days)
- Shifts (each turnover window, typically 2–4 hours, with push notifications to the cleaner)
- GPS punches (check-in / check-out with distance-from-the-pin verification)
- The Turnover Report form (rooms done, guest-ready, photos, damage, left items, restock, linen sets, notes) and every submission
- Timesheets (verified hours worked, exportable for hourly cleaners)

**Local SQLite database (`turnover-ops.db`, on your computer):**

- Hosts: name, contact, billing email, payment terms, which platform they use
- Units: address, bedrooms / bathrooms, turnover length, what the host pays, what the cleaner gets, per-unit time zone, ZenSched IDs
- Lockbox / door / alarm codes, wifi passwords, supplies-closet notes — **never leave your computer**
- Cleaners: contact, pay type (per turnover or hourly), hourly rate
- The week's turnovers: checkout and check-in times, the cleaning window, who is assigned, the shift id, the punch times, and a summary of each Turnover Report with photo links
- Optional recurring cleans (mid-stay refresh, weekly deep clean, inspection)
- Host invoices and cleaner payouts
- Your settings (default time zone, turnover length, start offset after checkout, invoice terms, form id)

**Never duplicated:** the live schedule, punches, timesheets, and photo files stay in ZenSched. The local database only stores *references* to them plus a per-turnover summary so you can answer "is the Casita ready?" without paying to re-read reports.

### Privacy note

Every access code, wifi password, alarm code, and the host's personal phone lives only in the local database: `units.access_notes` and `units.supplies_closet_notes`. `SKILL.md` forbids the AI from putting them into any ZenSched field, including location names and notes, event titles, cancellation reasons (cleaners see those), and form answers; the Turnover Report itself tells cleaners not to type codes into it. Give codes to your cleaners yourself, by whatever channel you trust. ZenSched only ever sees the unit's short name ("Marisol Vega - Palm St 12B"), the street address for the GPS pin, and the report the cleaner submits.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `shift_update`, `shift_status`, `form_submissions`, `timesheet_export`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `turnover-ops.db` on your computer.

Each week you paste the checkouts (from Hospitable, Turno, your Airbnb calendar, or by hand: unit, date, guest out, next guest in). The AI turns each into a turnover with a cleaning window (default: start 30 minutes after checkout, run for the unit's turnover length), flags any with too little slack before the next guest, and asks who takes what. "Dispatch" creates one shift per turnover on ZenSched, in each unit's own time zone. Your cleaner sees it in the app, checks in at the unit (GPS-verified), cleans, fills in the Turnover Report with photos, and checks out. During the day "who's at risk?" shows anything unassigned, anyone who hasn't checked in 15 minutes after their start, and any turnover ending within an hour of the guest's arrival. Same-day changes ("guest extended a night") move the shift on the cleaner's phone. Later, "record this week" pulls the completed shifts and the reports once, saves a summary with photo links, and leads with damage and left items. "Restock list" is one query. "Invoice everyone" and "pay run" come from the same records. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\turnover-ops`
- Mac: `/Users/yourname/turnover-ops`

The database file will be created automatically inside this folder the first time the AI uses it. It will contain your hosts' door codes; keep it on an encrypted, backed-up disk and out of shared folders.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\turnover-ops.db` (Windows) or `/turnover-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "turnover-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/turnover-ops/turnover-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\turnover-ops\\turnover-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Turnover Co" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my turnover-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run 51 statements and confirm the tables exist. The `turnover-ops.db` file now exists in your folder with default settings (3-hour turnovers starting 30 minutes after checkout, 7-day invoice terms) you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 turnover-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> We're Coastal Turnover Co in San Diego, Pacific time. Cleaners start half an hour after checkout and a standard turnover is 3 hours. Save that in settings and set up the Turnover Report form.

It writes those to the `settings` table, creates the Turnover Report form on ZenSched (free), and saves the form id so every unit gets it automatically.

**Check-in radius.** The default is 75 m around the geocoded pin. ZenSched enforces the radius through the account's policy, not per unit, and with geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-driveway circle. Condo towers and resort complexes are the common problem: the pin lands on the street and the unit is 50 m in and ten floors up. Ask the AI to "set the check-in radius to 150 m" (`policy_update`); it applies to every unit, still proves the cleaner was at the building, and is what the example uses. You can also ask it to "move the pin onto the building" (`location_update`, free). `remote_checkin` turns GPS verification off for every unit and should be a last resort, because it also turns off the proof.

**Forgotten check-outs.** Ask the AI to "remind cleaners to check out 15 minutes after the window ends" (`checkout_reminder_min_after`). If you would rather cleaners fix their own missed check-out in the app, ask for "let cleaners edit their times" (`timesheet_edit: "times_only"`); it is off by default.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered: creating a unit's location (geocoding, $0.03), inviting a cleaner ($0.25), each GPS-verified check-in or check-out ($0.10), reading a Turnover Report ($0.15 because it has photos; each report is billed once, ever), and a processed timesheet with breaks and overtime ($0.10; the plain hours export is free). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

**A normal turnover costs about $0.35** in ZenSched fees: two GPS punches and one photo report read. A crew doing 40 turnovers a week spends about $14 a week; the AI states the cost before it spends.

## Using it

Everything after setup is plain English. Examples:

- "New host: Marisol Vega, marisol@example.com, pays in 14 days. Three units: Palm St 12B, 12 Palm Street unit 12B, San Diego 92109, 2 bed 2 bath, $140 a turnover, cleaner gets $70, lockbox 0912, wifi PalmGuest / sunset2026 ..."
- "Add Dev Patel's loft in Denver, Mountain time, 2 hours, $110 / $55."
- "Invite Ana Reyes, ana@example.com, paid per turnover. Luis Ortega, luis@example.com, hourly $22.50."
- "Here's this week from Hospitable: ..." (paste the list)
- "Dispatch." / "Ana does all of Marisol's, Luis takes the loft."
- "What's today look like?" / "Who's at risk?"
- "Is Ana at Palm St?" / "Is Palm 12B ready?"
- "Palm St guest extended a night, checkout is now Friday at 11."
- "The Casita booking cancelled."
- "Record this week's turnovers."
- "Anything broken?" (open damage reports)
- "Restock list." / "What do I bring to Palm Street?"
- "Invoice everyone." / "Invoice Marisol."
- "Pay run."
- "Marisol paid INV-2026-0001." / "Who owes me money?"
- "Dev wants a Sunday inspection at the loft, 10am, one hour, $40."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Invoice everyone" records one invoice per host in your database (number, date, due date honoring that host's terms, count, amount, which turnovers) and the AI writes out a plain-text invoice you can paste into an email, with a line per turnover (date, unit, type, cleaner, amount) and a note that every turnover was GPS-verified with a photo report available. It does **not** generate a PDF, email it for you, or collect payment. Invoices never include codes or what you pay cleaners. When the host pays, tell the AI ("Marisol paid INV-2026-0001") and it marks it paid; "who owes me money?" shows aging.

### What "pay run" means here

"Pay run" totals what each cleaner is owed for completed, unpaid turnovers. Per-turnover cleaners get the flat amount snapshotted from each unit when the turnover was created (so a later price change does not rewrite history). Hourly cleaners get GPS-verified hours from ZenSched's free hours export times their rate; if you want break and overtime rules applied, the AI can run the processed timesheet ($0.10) once you tell it your pay week. It writes a per-cleaner summary you pay from and records the payout. The kit does not calculate taxes or pay anyone.

### What "proof for the host" means here

Every completed turnover has GPS check-in / check-out times with distance from the pin, a guest-ready Yes / No, and up to six photos the cleaner took. "Is Palm 12B ready?" answers from the local record with the photo links; you forward them. For a week's worth, the AI can pull a CSV export of a unit's reports (`form_export` with the unit's event) without re-paying for reports already read.

## Mobile app for cleaners

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [App Store](https://apps.apple.com/us/app/zensched/id6800081657)

When you invite a cleaner, they get an email, install the app, and can immediately see their turnovers, check in and out with GPS verification, and fill in the Turnover Report with photos. There is no signature step; the cleaner submits alone in the empty unit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `turnover-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Business or unit time zone not set | "Set my timezone offset to -07:00" (settings) or "Loft 4 is in Mountain time" (`units.tz_offset`) |
| Shift creation fails for dates a couple of months out | The unit's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Cleaner's check-in not GPS-verified at a condo tower or complex | Pin is on the street, unit is inside the building | "Set the check-in radius to 150 m" (`policy_update(0, {"checkin_radius_m": 150})`, applies to all units), or "move the pin onto the building" (`location_update`, free), or `location_refine` ($0.10). The radius is **not** a per-location setting. |
| Cleaner forgot to check out | Shift still `checked_in` | Tell the AI the real end time; ask for a 15-minute check-out reminder, or enable cleaner time edits |
| Cleaner does not see the Turnover Report | Form not assigned to that unit's event | "Attach the Turnover Report to the Casita event" (`form_assign`) |
| Turnover shows on the at-risk board but the cleaner is there | Check-in recorded on ZenSched, not yet copied locally | Ask "is Ana at Palm St?"; the AI checks `shift_status` and clears it |
| Guest extended but the shift did not move | The AI updated the date but not the window | Say "recompute the window"; `SKILL.md` requires an explicit `scheduled_start` / `scheduled_end` on updates and a `shift_update` |
| "Is Palm 12B ready" comes back with no photos | Turnover not recorded yet | "Record this week's turnovers" first; reading reports is metered, so the AI asks before doing it |
| Restock list still shows an item you already restocked | It shows the latest report per unit | It clears when the next report does not tick it |
| AI refuses to put a door code in ZenSched | Working as intended | Give it to the cleaner directly |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms, timesheets); SQLite is authoritative for hosts, units (including all access codes), roster, the booking-driven turnover board, recurrence, billing, and pay; each side stores only the other's IDs, plus a per-turnover summary and photo URLs cached locally because submission reads are metered. The privacy boundary is enforced by data placement (code columns exist only locally) and by `SKILL.md` rule 1; there is no technical control stopping a misbehaving agent, so review the rule if you swap models.

**Data model decisions.**

- **Turnovers are booking-driven, not recurring.** Unlike the recurring-visit kits, the primary scheduling input is a pasted list of checkouts. Each becomes a `turnovers` row with `checkout_time` and `checkin_time` (next guest); the `fill_turnover_defaults` trigger derives `scheduled_start` (checkout + `settings.default_start_offset_minutes`) and `scheduled_end` (+ `units.turnover_minutes`, else `settings.default_turnover_minutes`) in the unit's offset when they are left NULL. The trigger strips the offset (`substr(..., 1, 19)`) before adding minutes and re-appends it, because SQLite's `datetime()` would otherwise convert an offset string to UTC. It fires on insert only; on reschedule the agent recomputes the window explicitly (`SKILL.md` "Reschedule or cancel") and calls `shift_update`.
- **Optional recurrence** for cleans not tied to a booking (`recurring_cleans`: mid-stay refresh, deep clean, inspection). Same shape as the pet-care and home-care kits: 7-character Monday-first mask, `HH:MM`, 30–1440 minutes, `start_date`/`end_date`, preferred cleaner. `recurring_due_this_week` expands with a recursive CTE over the next seven days and drops dates that already have a `turnovers` row for that `recurring_id`; the agent inserts a turnover per row (with explicit `scheduled_*` from the view, since there is no checkout to derive from) and then dispatches like any other.
- **Units are long-lived; events roll.** One ZenSched location per unit, permanent (`units.zensched_location_id`, `location_create(name="<host> - <label>", street_address=..., checkin_radius_m=75, idempotency_key="loc-unit-{unit_id}")`). Events are capped at 60 days, so each unit holds its *current* event in `zensched_event_id` and `event_valid_until`; the agent creates a new one (`end_date = start + 59 days`, key `event-unit-{unit_id}-{YYYYMMDD}`) whenever a turnover date is later than `event_valid_until`, re-runs `form_assign`, and updates the row. `turnover_board.needs_event_roll` is per row; `events_expiring` lists units with upcoming work whose event ends within 14 days. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to ~300 ft.
- **Per-unit time zone.** `units.tz_offset` (`CHECK`-constrained to `±HH:MM`, filled from `settings.timezone_offset` by the `fill_unit_defaults` trigger when NULL) is used for every ISO string the views emit and for `local_today`, which is `date('now', ±N minutes)` computed from the unit's offset so that an evening Pacific session does not treat UTC-tomorrow as today. `turnovers_today`, `turnovers_upcoming`, and `turnovers_at_risk` filter on `local_today`; `recurring_due_this_week` and `events_expiring` use `date('now')` (UTC) for their 7- and 14-day horizons, which is close enough for a lookahead.
- **`turnover_board`** is the single base view (non-cancelled turnovers joined to unit, host, cleaner) with `zensched_name`, `start_iso`/`end_iso`, `slack_minutes` (minutes between `scheduled_end` and the next guest's check-in, via `julianday` on two offset-bearing strings), `tight_slack` (< 30, computed on the rounded value so 29.9999 does not disagree with a displayed 30), `worker_id`, `unassigned`, `needs_location`, `needs_event_roll`, `needs_shift`, and `idempotency_key`. `turnovers_today` / `turnovers_upcoming` (today + 6, excluding completed and missed) / `turnovers_unassigned` / `turnovers_at_risk` are filters over it. `turnovers_at_risk` is today's rows in `open`/`assigned`/`in_progress` that are unassigned, or have no `checkin_at` 15 minutes after `start_iso` (`julianday('now') > julianday(start_iso) + 15/1440`), or have `slack_minutes < 60`, with a `risk` label; it depends on the agent copying `checkin_at` from `shift_status`, which `SKILL.md` "Today's board" does.
- **Snapshots.** `host_amount` and `cleaner_amount` are copied from `units.host_price` / `units.cleaner_pay` by the insert trigger when NULL, so price changes never rewrite history; one-offs (a $40 inspection on a $110 unit) pass `host_amount` explicitly. `cleaner_amount` is per unit, not per cleaner, so a swap keeps it.
- **Two pay types.** `cleaners.pay_type` is `CHECK`-constrained to `per_turnover | hourly`. `cleaner_pay_due` groups completed unpaid turnovers per cleaner: `amount_due = SUM(cleaner_amount)` for per-turnover cleaners, `NULL` with `use_timesheet_export = 1` for hourly ones, so the agent knows to run `timesheet_export(period, mode="hours")` (free) and multiply by `pay_rate`. `cleaner_payouts` records each run with a JSON `turnover_ids` array (the view emits it via `json_group_array`).
- **Report summary columns** on `turnovers`: `rooms_done` and `restock_json` are JSON arrays of the form's option keys; `guest_ready`, `damage_flag`, `left_items` are 0/1; `photo_urls` and `damage_photo_urls` are JSON arrays of CDN URLs (the host-proof artifact, cached so a later question is free); `damage_ack` is the owner's acknowledgment and the only report-derived column the agent may change. `damage_reports_open` is `damage_flag = 1 AND damage_ack = 0`. `restock_needed` picks the **latest** completed report per unit (correlated subquery ordered by date then id) and excludes `["none"]`, `[]`, and NULL, ordered by host, city, address.
- `turnovers.zensched_shift_id` and `cleaners.zensched_worker_id` are `UNIQUE`. `turnover_type` (`turnover | mid_stay | deep_clean | inspection`), `status` (`open | assigned | in_progress | completed | missed | cancelled`), `checkout_time` / `checkin_time` (`HH:MM`), and the recurring mask/time/duration are `CHECK`-constrained.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`; `turnovers_to_invoice` carries `terms_days = COALESCE(hosts.payment_terms_days, settings.invoice_due_days)` and a `missing_price_count` so the agent asks before invoicing a unit with no price; `invoices_outstanding` adds `days_outstanding`, `days_overdue`, and an `aging_bucket` (`current | 1-30 | 31-60 | 61+`).
- **No signature field.** The Turnover Report deliberately has none: on ZenSched a signature field replaces the Submit button, and a cleaner alone in an empty unit has nobody to sign. Proof is the GPS punches plus required photos.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it. Deleting a host cascades to units, turnovers, and invoices; deleting a cleaner sets `turnovers.cleaner_id` and `recurring_cleans.preferred_cleaner_id` NULL and cascades `cleaner_payouts`.

**Turnover Report form.** Created once with `form_create(title, fields_json, idempotency_key="form-turnover-report")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's form validator (`_validate_fields`; 14 fields, well under the 80-field cap). Every field, including the three `section` headers, carries an explicit `identifier` so submission `data` keys are stable (`rooms_done`, `guest_ready`, `photos_ready`, `damage`, `damage_notes`, `damage_photos`, `left_items`, `left_items_notes`, `restock`, `linen_sets`, `notes`); the sections are `sec_guest_ready`, `sec_issues`, `sec_restock` because a section labelled "Restock" would otherwise auto-derive the same identifier as the `restock` multi-select. Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`), so `No - see notes` comes back as `no___see_notes`, `Outdoor / balcony` as `outdoor___balcony`, `Shampoo / conditioner` as `shampoo___conditioner`, `Coffee / tea` as `coffee___tea`; `SKILL.md` lists the full mapping. Three `show_if` rules reference `damage` and `left_items` with value `yes`; those detail fields stay hidden on the phone until the answer is yes. `photos_ready` is `required` with `max_images: 6`; `damage_photos` is optional with `max_images: 3`. Attaching is `form_assign(form_id, event_id=...)`, which resolves event → brand → policy and installs the form on the phone for every subsequent `shift_create`.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-unit-{unit_id}`
- event: `event-unit-{unit_id}-{YYYYMMDD window start}`
- shift: `shift-turnover-{turnover_id}`; after cancel-and-recreate for a new cleaner, `shift-turnover-{turnover_id}-w{worker_id}`
- shift update: `update-shift-{shift_id}-{YYYYMMDDHHMM of the new start}`
- cancel: `cancel-shift-{shift_id}`
- worker: `worker-{email}`
- form: `form-turnover-report`; assignment: `assign-report-{event_id}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` and `shift_update` take `start` and `end` in ISO 8601 with an explicit offset. Always use the **unit's** offset from `units.tz_offset` (e.g. `2026-09-07T11:30:00-07:00`, `2026-09-08T10:30:00-06:00` for a Denver unit), never `Z`. The trigger and views build these strings so the agent does not have to. `turnovers.scheduled_*`, `checkin_at`, and `checkout_at` use the same format so `julianday` arithmetic (slack, at-risk) is exact.

**Metered reads.** `form_submissions` and `form_export` bill $0.15 per Turnover Report read (it always has photos), once per submission ever; `form_export` is preferred for a week at a time, and `form_submissions(form_id, event_id=...)` for one unit. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free; `mode="processed"` is $0.10 and needs `account_set_payroll_period`. The hours export returns `worker_id, worker_name, event_id, date, hours, gps_verified` per row plus `summary_hours_per_worker`, which is what the hourly pay run uses.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its 51 statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) twice for idempotency (seed rows not duplicated), then exercising: all 8 tables, 12 views, and 8 triggers present; every view on an empty database and again with data; `fill_unit_defaults` (tz from settings, explicit tz kept); `fill_turnover_defaults` (window from checkout + 30 min in the unit's offset for `-07:00` and `-06:00` units, end from unit vs settings turnover minutes, snapshots, explicit values preserved, NULLs when there is no checkout time, snapshot unchanged after a unit price change); the `updated_at` triggers on all five tables; `turnovers_upcoming` window (today..+6 in the unit's local date, excluding +7, cancelled, completed), `start_iso`/`end_iso` offsets, `idempotency_key`, `slack_minutes` math and `tight_slack` at exactly 30, per-unit `local_today`, the `unassigned`/`needs_shift`/`needs_location`/`needs_event_roll` flags and `needs_event_roll` flipping exactly after `event_valid_until`; `turnovers_today` and `turnovers_unassigned`; `turnovers_at_risk` for all three risk labels plus non-flagging of checked-in, comfortable, completed, and tomorrow rows; `recurring_due_this_week` against Mon/Wed/Fri and daily masks (3 and 7 rows on the right weekdays), unit offsets, an end crossing midnight, preferred-cleaner join, exclusion of already-inserted dates, `end_date`, and `is_active`; `events_expiring` (no event + recurring → listed; 30 days out → not; 10 days → listed; idle unit gains a turnover → listed); `UNIQUE` on `zensched_shift_id`, `zensched_worker_id`, `invoice_number`; `damage_reports_open` and acknowledgment; `restock_needed` latest-per-unit with `["none"]` excluded and host ordering; `turnovers_to_invoice` totals, `missing_price_count`, and terms fallback; `cleaner_pay_due` per-turnover sums vs hourly flag and `turnover_ids`; invoice numbering with prefix change and explicit number; `invoices_outstanding` aging buckets and `days_overdue`; `cleaner_payouts` and the `cleaner_paid` filter; every `CHECK` (pay type, tz format incl. `+05:30`, turnover minutes, weekday mask length and characters, start time, duration, both `turnover_type`s, status, checkout and check-in time); foreign keys, host cascade through units → turnovers → invoices, and cleaner delete → set-null on turnovers and recurring, cascade on payouts. 118 checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
