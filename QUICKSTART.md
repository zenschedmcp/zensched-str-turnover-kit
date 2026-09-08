# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What ZenSched does and does not do for turnovers" section of `README.md`. Short version: no calendar sync (you paste the week's checkouts), no host portal (you forward the photo links), no payments (invoices are text you email), and door codes stay on your computer.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\turnover-ops` (Windows) or `/Users/yourname/turnover-ops` (Mac). Note the full path. It will hold your hosts' door codes, so keep it on an encrypted, backed-up disk.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\turnover-ops\\turnover-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Turnover Co". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my turnover-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Coastal Turnover Co in San Diego, Pacific time. Cleaners start half an hour after checkout and a standard turnover is 3 hours. Hosts pay within 7 days. Save that to settings and create the Turnover Report form.

The AI saves your settings and calls `form_create` once (free) to build the Turnover Report your cleaners fill in: rooms completed, guest-ready Yes / No, up to six guest-ready photos, damage flag with notes and photos, items the guest left, a restock checklist, linen sets used, and a note. No signature step, so a cleaner can submit alone in the unit. It stores the form id so every unit gets it.

## 6. Add your first host and units

> New host: Marisol Vega, marisol@example.com, 619-555-0101, pays in 14 days, Airbnb and VRBO through Hospitable. Palm St 12B: 12 Palm Street unit 12B, San Diego 92109, 2 bed 2 bath condo tower, $140 a turnover, cleaner gets $70, lobby code 4411#, lockbox 0912, wifi PalmGuest / sunset2026. Casita: 5 Oak Avenue, San Diego 92104, 1 bed 1 bath, 2.5 hours, $120 / $60, lockbox 2288 on the side gate.

Behind the scenes the AI inserts the host and units (codes and wifi local only); calls `location_create` for "Marisol Vega - Palm St 12B" and "Marisol Vega - Casita" (geocode, $0.03 each, may trigger the $5 activation deposit the first time); creates a 60-day `event_create` per unit; attaches the Turnover Report with `form_assign`; and saves the IDs. Because Palm St is a condo tower, it will suggest widening the check-in radius to 150 m; that is a policy setting for all units (`policy_update`), not something on one location. Say yes.

A unit in another time zone just needs you to say so ("Dev's loft in Denver, Mountain time"); every shift for that unit is created in its own local time.

## 7. Invite your cleaners

> Invite Ana Reyes, ana@example.com, paid per turnover. And Luis Ortega, luis@example.com, hourly at $22.50.

Each gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS App Store](https://apps.apple.com/us/app/zensched/id6800081657)), and activates. Give them the door codes yourself; the AI will not put them in ZenSched.

## 8. Load the week and dispatch

Paste your checkouts, from Hospitable / Turno / your Airbnb calendar or by hand:

> Here's this week: Palm St 12B Mon 9/7 out 11 next in 4. Casita Wed 9/9 out 10 in 3. Palm St 12B Thu 9/10 out 11 in 4. Ana does all of Marisol's.

The AI makes one turnover per line with a cleaning window (checkout + 30 min, for the unit's turnover length), warns you if any window ends too close to the next guest, and lists anything unassigned. Then:

> Dispatch.

One shift per turnover goes to ZenSched in the unit's time zone; Ana gets a push per shift with the Turnover Report attached. She checks in at the unit (GPS-verified, $0.10), cleans, takes the photos, fills in the report, and checks out ($0.10).

## 9. During the week

> Who's at risk?

Anything unassigned today, anyone not checked in 15 minutes after their start (the AI checks ZenSched before alarming), and any turnover ending within an hour of the guest's arrival.

> Palm St guest extended a night. Checkout is now Friday at 11, guest in at 4.

The AI moves the turnover, recomputes the window around Ana's other Friday job, and updates the shift on her phone (`shift_update`, not a cancellation).

## 10. After the work is done

> Record this week's turnovers.

The AI pulls the completed, GPS-verified shifts and their times from ZenSched (free), then the Turnover Reports (metered, $0.15 each because of photos, so it tells you the cost first), saves a per-turnover summary with photo links, and leads with damage and left items.

> Is Palm 12B ready?

Answered from the local record, free: check-out time, GPS-verified, guest-ready, and the photo links to forward to Marisol.

> Restock list.

The latest report per unit that asked for supplies, grouped by host and street.

> Invoice everyone.

One plain-text invoice per host, honoring each host's payment terms, one line per turnover, with the total and a note that every turnover was GPS-verified with photos available. Nothing about codes or cleaner pay.

> Pay run.

What each cleaner is owed: per-turnover cleaners from the flat amount per unit, hourly cleaners from ZenSched's free verified-hours export times their rate. Say "paid" and it records the payout.

> Marisol paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the boundaries (no calendar sync, no portal, no payments), troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
