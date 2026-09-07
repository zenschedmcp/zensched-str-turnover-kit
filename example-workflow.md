# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: lockbox codes, wifi passwords, alarm codes, the hosts' phone numbers, prices. ZenSched sees `Marisol - Palm St 12B`, a street address, a 3-hour shift, and a photo report.

The business is **Coastal Turnover Co**, San Diego, Pacific time (`-07:00`). It is Saturday, September 5, 2026.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Turnover Co, timezone_offset = -05:00, invoice_due_days = 7,
    invoice_prefix = INV, turnover_form_id = NULL, default_turnover_minutes = 180,
    default_start_offset_minutes = 30, event_window_days = 60, default_checkin_radius_m = 75
sqlite_query:   SELECT * FROM turnovers_at_risk;      → (none)
sqlite_query:   SELECT * FROM damage_reports_open;    → (none)
```

## "We're Coastal Turnover Co in San Diego, Pacific time. Cleaners start half an hour after checkout and a standard turnover is 3 hours. Hosts pay within 7 days."

```
sqlite_execute: UPDATE settings SET value = 'Coastal Turnover Co' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-07:00' WHERE key = 'timezone_offset';
```

(180 minutes, 30 minutes, and 7 days are already the defaults.)

> Saved. New units will be scheduled in Pacific time unless you tell me a unit is somewhere else. You don't have a Turnover Report form yet; it's free to create and every clean comes back with guest-ready photos, a damage flag, left-items note, restock checklist, and linen count. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Turnover Report"
  idempotency_key: "form-turnover-report"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Guest-ready check", "identifier": "sec_guest_ready", "text": "Fill this in before you leave the unit. Photos are what the host sees. Never write door codes or wifi passwords here."},
  {"type": "multi_select", "label": "Rooms completed", "identifier": "rooms_done", "required": true,
   "options": ["Kitchen", "Living room", "Bedroom 1", "Bedroom 2", "Bedroom 3", "Bathroom 1", "Bathroom 2", "Outdoor / balcony", "Laundry"]},
  {"type": "select", "label": "Unit is guest-ready", "identifier": "guest_ready", "required": true,
   "options": ["Yes", "No - see notes"]},
  {"type": "photo", "label": "Guest-ready photos (beds, bath, kitchen, living)", "identifier": "photos_ready", "required": true, "max_images": 6},
  {"type": "section", "label": "Issues", "identifier": "sec_issues", "text": "Anything the host needs to know about before the next guest arrives."},
  {"type": "select", "label": "Damage or maintenance issue found?", "identifier": "damage", "required": true,
   "options": ["No", "Yes"]},
  {"type": "textarea", "label": "Describe the damage / issue", "identifier": "damage_notes",
   "show_if": {"field": "damage", "op": "equals", "value": "yes", "action": "show"}},
  {"type": "photo", "label": "Damage photos", "identifier": "damage_photos", "max_images": 3,
   "show_if": {"field": "damage", "op": "equals", "value": "yes", "action": "show"}},
  {"type": "select", "label": "Guest left items behind?", "identifier": "left_items", "required": true,
   "options": ["No", "Yes"]},
  {"type": "textarea", "label": "What was left and where you put it", "identifier": "left_items_notes",
   "show_if": {"field": "left_items", "op": "equals", "value": "yes", "action": "show"}},
  {"type": "section", "label": "Restock", "identifier": "sec_restock", "text": "Tick anything running low so the office can restock before the next turnover."},
  {"type": "multi_select", "label": "Needs restocking", "identifier": "restock", "required": true,
   "options": ["Toilet paper", "Paper towels", "Hand soap", "Dish soap", "Shampoo / conditioner", "Body wash", "Coffee / tea", "Trash bags", "Dishwasher pods", "Laundry pods", "Sponges", "Batteries", "None"]},
  {"type": "number", "label": "Linen sets used", "identifier": "linen_sets", "required": true},
  {"type": "textarea", "label": "Notes for the host / office", "identifier": "notes"}
]
```

```
  → form_id: 301, fields: [ ...14 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '301' WHERE key = 'turnover_form_id';
```

> Turnover Report form created. I'll attach it to every unit automatically. Damage and left-item follow-ups stay hidden on the phone until the answer is Yes. There's deliberately no signature step, so the cleaner can submit alone in the unit.

## "New host: Marisol Vega, marisol@example.com, 619-555-0101, pays in 14 days, she's on Airbnb and VRBO through Hospitable. Three units. Palm St 12B: 12 Palm Street unit 12B, San Diego 92109, 2 bed 2 bath condo tower, $140 a turnover, I pay the cleaner $70, lobby code 4411#, unit lockbox 0912, wifi PalmGuest / sunset2026. Casita: 5 Oak Avenue, San Diego 92104, 1 bed 1 bath, 2.5 hours, $120 / $60, lockbox 2288 on the side gate. Beach House: 880 Ocean Blvd, Carlsbad 92008, 3 bed 2 bath, 4 hours, $210 / $105, keypad 7731, alarm 2580, supplies closet in the garage code 1234."

```
sqlite_execute:
  INSERT INTO hosts (name, contact, billing_email, payment_terms_days, platform_notes)
  VALUES ('Marisol Vega', '619-555-0101', 'marisol@example.com', 14, 'Airbnb + VRBO via Hospitable');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO units (host_id, label, address, city, region, country, postal, bedrooms, bathrooms, turnover_minutes,
                     host_price, cleaner_pay, access_notes)
  VALUES (1, 'Palm St 12B', '12 Palm Street, Unit 12B', 'San Diego', 'CA', 'US', '92109', 2, 2, 180,
          140.00, 70.00, 'Lobby code 4411#. Unit lockbox 0912. Wifi PalmGuest / sunset2026.');
  → 1   (tz_offset left NULL → trigger fills -07:00)

sqlite_execute:
  INSERT INTO units (host_id, label, address, city, region, country, postal, bedrooms, bathrooms, turnover_minutes,
                     host_price, cleaner_pay, access_notes)
  VALUES (1, 'Casita', '5 Oak Avenue', 'San Diego', 'CA', 'US', '92104', 1, 1, 150,
          120.00, 60.00, 'Lockbox 2288 on the side gate.');
  → 2

sqlite_execute:
  INSERT INTO units (host_id, label, address, city, region, country, postal, bedrooms, bathrooms, turnover_minutes,
                     host_price, cleaner_pay, access_notes, supplies_closet_notes)
  VALUES (1, 'Beach House', '880 Ocean Blvd', 'Carlsbad', 'CA', 'US', '92008', 3, 2, 240,
          210.00, 105.00, 'Keypad 7731. Alarm 2580.', 'Supplies closet in the garage, code 1234.');
  → 3
```

Agent (first metered call this session, rule 9):

> Creating the three units on ZenSched costs $0.09 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Marisol Vega - Palm St 12B"
  street_address: "12 Palm Street, San Diego, CA 92109"
  checkin_radius_m: 75
  idempotency_key: "loc-unit-1"
  → location_id: 9001, lat: 32.7960, lng: -117.2510, pin_quality: "street",
    satellite_url: "https://...", radius_note: "Check-in radius is enforced by the talent policy ...",
    billing: { meter: "geocode", units: 1, price: 0.03 }

location_create: name "Marisol Vega - Casita", street_address "5 Oak Avenue, San Diego, CA 92104", checkin_radius_m 75, idempotency_key "loc-unit-2"
  → location_id 9002, pin_quality "street"
location_create: name "Marisol Vega - Beach House", street_address "880 Ocean Blvd, Carlsbad, CA 92008", checkin_radius_m 75, idempotency_key "loc-unit-3"
  → location_id 9003, pin_quality "street"
```

Nothing about the lobby code, lockbox, wifi, alarm, or closet is in `name` or `notes`. Those live only in `units.access_notes` and `units.supplies_closet_notes`. The unit number is not sent either; the pin is the building.

```
event_create:
  location_id: 9001
  title: "Turnovers - Marisol Vega - Palm St 12B"
  start_date: "2026-09-05"
  end_date:   "2026-11-03"          ← start + 59 days (60-day cap)
  idempotency_key: "event-unit-1-20260905"
  → event_id: 7001

form_assign:
  form_id: 301
  event_id: 7001
  idempotency_key: "assign-report-7001"
  → status: "assigned", form_id: 301, event_id: 7001, policy_id: 0

sqlite_execute: UPDATE units SET zensched_location_id = 9001, zensched_event_id = 7001, event_valid_until = '2026-11-03' WHERE unit_id = 1;

event_create: location_id 9002, title "Turnovers - Marisol Vega - Casita", start_date "2026-09-05", end_date "2026-11-03", idempotency_key "event-unit-2-20260905"  → event_id 7002
form_assign:  form_id 301, event_id 7002, idempotency_key "assign-report-7002"
sqlite_execute: UPDATE units SET zensched_location_id = 9002, zensched_event_id = 7002, event_valid_until = '2026-11-03' WHERE unit_id = 2;

event_create: location_id 9003, title "Turnovers - Marisol Vega - Beach House", start_date "2026-09-05", end_date "2026-11-03", idempotency_key "event-unit-3-20260905"  → event_id 7003
form_assign:  form_id 301, event_id 7003, idempotency_key "assign-report-7003"
sqlite_execute: UPDATE units SET zensched_location_id = 9003, zensched_event_id = 7003, event_valid_until = '2026-11-03' WHERE unit_id = 3;
```

> Added Marisol Vega with three units: Palm St 12B ($140, 3 h), Casita ($120, 2.5 h), Beach House ($210, 4 h). Her codes and wifi are saved on your computer only; ZenSched knows the units as "Marisol Vega - Palm St 12B" and so on, with the street address for GPS. Each unit's ZenSched event runs through Nov 3; I'll renew them automatically.
>
> One thing about Palm St 12B: it's a condo tower and the GPS pin landed on the street outside. Unit 12B is probably 40–60 m from that pin and several floors up, so a cleaner checking in from inside the unit could fall outside the default radius. The radius is a policy setting that applies to all your units, not something on this one location. I'd suggest widening it to 150 m so tower and complex units verify reliably while still proving the cleaner was at the building. Want me to do that?

Owner: *"yes, 150"*

```
policy_get: policy_id 0
  → { geofence_enabled: true, require_on_site: true, checkin_radius_m: 91, ... }

policy_update:
  policy_id: 0
  settings_json: "{\"checkin_radius_m\": 150, \"checkout_reminder_min_after\": 15}"
  idempotency_key: "policy-0-20260905"
  → updated: { checkin_radius_m: 150, checkout_reminder_min_after: 15 }
```

> Done: 150 m check-in radius for every unit, and cleaners get a reminder 15 minutes after their window ends if they forgot to check out.

## "Second host: Dev Patel, dev@example.com, 720-555-0202, standard terms. One unit in Denver: Loft 4, 9 Mill Road, Denver 80202, 1 bed 1 bath, 2 hours, $110 / $55. Smart lock code changes every stay, he texts it to me; wifi MillLoft / bikes4ever."

```
sqlite_execute: INSERT INTO hosts (name, contact, billing_email, platform_notes) VALUES ('Dev Patel', '720-555-0202', 'dev@example.com', 'Airbnb; texts smart-lock code per stay');   → 2
sqlite_execute:
  INSERT INTO units (host_id, label, address, city, region, country, postal, tz_offset, bedrooms, bathrooms, turnover_minutes,
                     host_price, cleaner_pay, access_notes)
  VALUES (2, 'Loft 4', '9 Mill Road', 'Denver', 'CO', 'US', '80202', '-06:00', 1, 1, 120,
          110.00, 55.00, 'Smart lock code per stay (Dev texts it). Wifi MillLoft / bikes4ever.');   → 4

location_create: name "Dev Patel - Loft 4", street_address "9 Mill Road, Denver, CO 80202", checkin_radius_m 75, idempotency_key "loc-unit-4"  → location_id 9004
event_create:    location_id 9004, title "Turnovers - Dev Patel - Loft 4", start_date "2026-09-05", end_date "2026-11-03", idempotency_key "event-unit-4-20260905"  → event_id 7004
form_assign:     form_id 301, event_id 7004, idempotency_key "assign-report-7004"
sqlite_execute:  UPDATE units SET zensched_location_id = 9004, zensched_event_id = 7004, event_valid_until = '2026-11-03' WHERE unit_id = 4;
```

`payment_terms_days` is left NULL, so Dev bills on the 7-day default. `tz_offset` is `-06:00`, so every Loft 4 shift is created in Mountain time. The agent does not re-ask about the $0.03 (geocoding was approved this session).

> Added Dev Patel and Loft 4 in Denver, Mountain time ($110, 2 h). I'll schedule that unit in its own time zone.

## "Invite Ana Reyes, ana@example.com, she's paid per turnover. And Luis Ortega, luis@example.com, he's in Denver, hourly at $22.50."

> Inviting two cleaners costs $0.50. OK?

Owner: *"yes"*

```
worker_invite:
  email: "ana@example.com"
  first_name: "Ana"
  last_name: "Reyes"
  idempotency_key: "worker-ana@example.com"
  → worker_id: 501, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

worker_invite: email "luis@example.com", first_name "Luis", last_name "Ortega", idempotency_key "worker-luis@example.com"  → worker_id 502

sqlite_execute: INSERT INTO cleaners (name, email, zensched_worker_id, pay_type) VALUES ('Ana Reyes', 'ana@example.com', 501, 'per_turnover');   → 1
sqlite_execute: INSERT INTO cleaners (name, email, zensched_worker_id, pay_type, pay_rate) VALUES ('Luis Ortega', 'luis@example.com', 502, 'hourly', 22.50);   → 2
```

> Invited Ana and Luis. Each gets an email with the app link and an activation code. Ana is paid the per-turnover amount on each unit ($70 / $60 / $105); Luis is paid $22.50 an hour from his GPS-verified time. Please give Ana Marisol's codes and Luis the Loft 4 wifi yourself; I keep those off ZenSched on purpose.

## "Here's this week from Hospitable:

```
Palm St 12B    Mon 9/7    out 11:00   next in 16:00
Casita         Wed 9/9    out 10:00   next in 15:00
Beach House    Tue 9/8    out 11:00   next in 16:00
Loft 4         Tue 9/8    out 10:00   next in 15:00
Palm St 12B    Thu 9/10   out 11:00   next in 16:00
Casita         Fri 9/11   out 09:00   next in 14:00
```

Ana does all of Marisol's, Luis does the loft."

```
sqlite_query: SELECT unit_id, label, tz_offset, turnover_minutes FROM units WHERE is_active = 1;
  → 1 Palm St 12B -07:00 180 | 2 Casita -07:00 150 | 3 Beach House -07:00 240 | 4 Loft 4 -06:00 120
sqlite_query: SELECT turnover_id FROM turnovers WHERE unit_id IN (1,2,3,4) AND turnover_date BETWEEN '2026-09-07' AND '2026-09-11' AND status <> 'cancelled';
  → (none)

sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (1, '2026-09-07', '11:00', '16:00', 1);   → 1
sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (2, '2026-09-09', '10:00', '15:00', 1);   → 2
sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (3, '2026-09-08', '11:00', '16:00', 1);   → 3
sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (4, '2026-09-08', '10:00', '15:00', 2);   → 4
sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (1, '2026-09-10', '11:00', '16:00', 1);   → 5
sqlite_execute: INSERT INTO turnovers (unit_id, turnover_date, checkout_time, checkin_time, cleaner_id) VALUES (2, '2026-09-11', '09:00', '14:00', 1);   → 6
```

`scheduled_start`, `scheduled_end`, `host_amount`, and `cleaner_amount` were left NULL; the `fill_turnover_defaults` trigger set them (row 1: `2026-09-07T11:30:00-07:00` to `14:30:00-07:00`, $140 / $70; row 4: `2026-09-08T10:30:00-06:00` to `12:30:00-06:00`, $110 / $55).

```
sqlite_query: SELECT * FROM turnovers_upcoming WHERE needs_shift = 1;
  → 2026-09-07 | t1 | Palm St 12B | Marisol Vega - Palm St 12B | evt 7001 | needs_event_roll 0 | needs_location 0
               | 11:30–14:30 -07:00 | guest in 16:00 | slack 90 | tight 0 | Ana Reyes (501) | shift-turnover-1
    2026-09-08 | t3 | Beach House | ... evt 7003 | 11:30–15:30 -07:00 | guest in 16:00 | slack 30 | tight 0 | Ana | shift-turnover-3
    2026-09-08 | t4 | Loft 4      | Dev Patel - Loft 4 | evt 7004 | 10:30–12:30 -06:00 | guest in 15:00 | slack 150 | Luis Ortega (502) | shift-turnover-4
    2026-09-09 | t2 | Casita      | ... evt 7002 | 10:30–13:00 -07:00 | guest in 15:00 | slack 120 | Ana | shift-turnover-2
    2026-09-10 | t5 | Palm St 12B | ... evt 7001 | 11:30–14:30 -07:00 | guest in 16:00 | slack 90 | Ana | shift-turnover-5
    2026-09-11 | t6 | Casita      | ... evt 7002 | 09:30–12:00 -07:00 | guest in 14:00 | slack 120 | Ana | shift-turnover-6
  (6 rows)
```

> Loaded 6 turnovers for Sep 7–11. One to watch: **Beach House Tuesday** — guest out 11:00, next in 16:00, and it's a 4-hour clean, so Ana finishes 15:30 with only 30 minutes to spare. Want me to start her at 11:15, or is 30 minutes fine? Everything else has 90 minutes or more. Nobody's dispatched yet; say "dispatch" and I'll put the shifts on their phones.

Owner: *"30 is fine. Dispatch."*

```
shift_create:
  event_id: 7001
  worker_id: 501
  start: "2026-09-07T11:30:00-07:00"
  end:   "2026-09-07T14:30:00-07:00"
  idempotency_key: "shift-turnover-1"
  → shift_id: 88001, status: "scheduled", forms_installed: [301]
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88001, zensched_event_id = 7001, status = 'assigned' WHERE turnover_id = 1;

shift_create: event_id 7003, worker_id 501, start "2026-09-08T11:30:00-07:00", end "2026-09-08T15:30:00-07:00", idempotency_key "shift-turnover-3"  → 88003
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88003, zensched_event_id = 7003, status = 'assigned' WHERE turnover_id = 3;

shift_create: event_id 7004, worker_id 502, start "2026-09-08T10:30:00-06:00", end "2026-09-08T12:30:00-06:00", idempotency_key "shift-turnover-4"  → 88004
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88004, zensched_event_id = 7004, status = 'assigned' WHERE turnover_id = 4;

shift_create: event_id 7002, worker_id 501, start "2026-09-09T10:30:00-07:00", end "2026-09-09T13:00:00-07:00", idempotency_key "shift-turnover-2"  → 88002
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88002, zensched_event_id = 7002, status = 'assigned' WHERE turnover_id = 2;

shift_create: event_id 7001, worker_id 501, start "2026-09-10T11:30:00-07:00", end "2026-09-10T14:30:00-07:00", idempotency_key "shift-turnover-5"  → 88005
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88005, zensched_event_id = 7001, status = 'assigned' WHERE turnover_id = 5;

shift_create: event_id 7002, worker_id 501, start "2026-09-11T09:30:00-07:00", end "2026-09-11T12:00:00-07:00", idempotency_key "shift-turnover-6"  → 88006
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88006, zensched_event_id = 7002, status = 'assigned' WHERE turnover_id = 6;
```

> Dispatched 6 turnovers:
> - **Ana:** Mon Palm St 12B 11:30–14:30 · Tue Beach House 11:30–15:30 · Wed Casita 10:30–13:00 · Thu Palm St 12B 11:30–14:30 · Fri Casita 9:30–12:00
> - **Luis:** Tue Loft 4 10:30–12:30 Mountain time
>
> Both have the shifts on their phones with the Turnover Report attached. Remember Ana needs Marisol's codes from you.

The Loft 4 shift went to ZenSched as `-06:00` because that unit's `tz_offset` is Mountain; the others as `-07:00`. Running "dispatch" again would return the same six shifts (same idempotency keys) and skip the rows because `needs_shift` is now 0.

## Wednesday morning: "Palm St guest asked to stay another night. Marisol said yes. Checkout is now Friday at 11, next guest still Friday at 4."

Palm St 12B's Thursday turnover (row 5, shift 88005) moves to Friday. Ana already has the Casita Friday 9:30–12:00.

```
sqlite_query: SELECT turnover_id, zensched_shift_id, zensched_event_id, status FROM turnovers WHERE unit_id = 1 AND turnover_date = '2026-09-10';
  → 5 | 88005 | 7001 | assigned
sqlite_query: SELECT turnover_id, unit_label, start_iso, end_iso FROM turnover_board WHERE cleaner_id = 1 AND turnover_date = '2026-09-11';
  → 6 | Casita | 2026-09-11T09:30:00-07:00 | 2026-09-11T12:00:00-07:00
```

The default window (checkout 11:00 + 30 min = 11:30–14:30) would overlap the Casita until 12:00, so the agent proposes starting after the Casita instead, and checks the slack: 12:15 + 3 h = 15:15, guest at 16:00, 45 minutes.

> Moving it to Friday. Ana finishes the Casita at 12:00, so I'd start Palm St at 12:15 and she'd be done 15:15 — 45 minutes before the 16:00 guest, tighter than usual but workable. Or I can keep 11:30 and give the Casita to someone else. Which?

Owner: *"12:15 is fine"*

```
sqlite_execute:
  UPDATE turnovers
  SET turnover_date = '2026-09-11', checkout_time = '11:00', checkin_time = '16:00',
      scheduled_start = '2026-09-11T12:15:00-07:00', scheduled_end = '2026-09-11T15:15:00-07:00',
      notes = 'Guest extended one night; moved from Thu 9/10. Starts after Casita.'
  WHERE turnover_id = 5;

shift_update:
  shift_id: 88005
  start: "2026-09-11T12:15:00-07:00"
  end:   "2026-09-11T15:15:00-07:00"
  idempotency_key: "update-shift-88005-202609111215"
  → shift_id: 88005, status: "scheduled", start: "2026-09-11T12:15:00-07:00", end: "2026-09-11T15:15:00-07:00"
```

> Done. Ana's Palm St 12B turnover is now Friday 12:15–15:15, right after the Casita; her phone shows it moved, not cancelled. Friday's 45-minute slack will show up on the at-risk board that morning so we keep an eye on it.

The new date (Sep 11) is inside the unit's event window (through Nov 3), so `shift_update` was enough. Had it been past `event_valid_until`, the agent would have rolled the event, cancelled 88005 with key `cancel-shift-88005`, and created a new shift with key `shift-turnover-5-w501`.

## The cleaners do the work

Monday 11:26, at 12 Palm Street, in the ZenSched app: Ana taps **Check in** (GPS: 38 m from the pin, inside the 150 m radius, verified, $0.10). Strips beds, two bathrooms, kitchen, living room, balcony. Opens **Turnover Report**: Rooms completed = Kitchen, Living room, Bedroom 1, Bedroom 2, Bathroom 1, Bathroom 2, Outdoor / balcony; Unit is guest-ready = Yes; six photos; Damage = No; Left items = No; Needs restocking = Toilet paper, Coffee / tea; Linen sets used = 2; Notes = "Balcony chairs wiped, guest left the AC on 65." Taps **Submit**. **Check out** 14:12 (verified).

Tuesday, Beach House: check in 11:24. Report: all rooms; guest-ready = Yes; 6 photos; **Damage = Yes**, "Cracked floor tile by the shower drain in bathroom 1, sharp edge, taped it over for now", 2 photos; Left items = No; Restock = None; Linen sets = 3. Check out 15:22.

Tuesday, Denver, Loft 4: Luis checks in 10:28 Mountain, out 12:37. Report: Kitchen, Living room, Bedroom 1, Bathroom 1; guest-ready Yes; 4 photos; no damage; no left items; Restock = Paper towels; Linen sets = 1.

Wednesday, Casita: Ana in 10:31, out 12:48. Guest-ready Yes; no damage; **Left items = Yes**, "White phone charger and a paperback on the nightstand, both in the kitchen drawer"; Restock = Trash bags, Dish soap; Linen sets = 1.

Friday: Casita 9:27–11:52 (Restock = None, linen 1). Palm St 12B 12:16–15:04 (Restock = Dishwasher pods, linen 2).

## Friday 13:05: "Is Ana at Palm St?"

```
sqlite_query: SELECT * FROM turnovers_at_risk;
  → 2026-09-11 | t5 | Palm St 12B | 12:15–15:15 | guest in 16:00 | slack 45 | status assigned | checkin_at NULL | risk: tight_slack
```

Row 5 is on the at-risk board for its 45-minute slack (under 60), and it is 50 minutes past the start with no check-in recorded locally yet, so the agent checks ZenSched rather than guessing:

```
shift_status: shift_id 88005
  → status "checked_in", actual_in "2026-09-11T12:16:40-07:00", actual_out null,
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 41 } ]

sqlite_execute: UPDATE turnovers SET status = 'in_progress', checkin_at = '2026-09-11T12:16:40-07:00', gps_verified = 1 WHERE turnover_id = 5;
```

> Yes. Ana checked in at 12:16, GPS-verified at the building (41 m from the pin). Window runs to 15:15, guest at 16:00. I'll flag it if she hasn't checked out by 15:30.

Free: `shift_status` is not metered.

## Saturday: "Record this week's turnovers."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-11"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88001, event_id: 7001, worker_id: 501, date: "2026-09-07", start: "11:30", end: "14:30", status: "checked_out" },
      { shift_id: 88003, event_id: 7003, worker_id: 501, date: "2026-09-08", ... },
      { shift_id: 88004, event_id: 7004, worker_id: 502, date: "2026-09-08", ... },
      { shift_id: 88002, event_id: 7002, worker_id: 501, date: "2026-09-09", ... },
      { shift_id: 88006, event_id: 7002, worker_id: 501, date: "2026-09-11", ... },
      { shift_id: 88005, event_id: 7001, worker_id: 501, date: "2026-09-11", start: "12:15", end: "15:15", ... }
    ], count: 6

sqlite_query: SELECT turnover_id, zensched_shift_id, status, report_dc_id FROM turnovers WHERE zensched_shift_id IN (88001, 88002, 88003, 88004, 88005, 88006);
  → all six present, none completed yet

timesheet_export:
  period: "2026-09-07:2026-09-11"
  mode:   "hours"
  format: "json"
  → row_count 6, rows: [
      { worker_id: 501, worker_name: "Ana Reyes",   event_id: 7001, date: "2026-09-07", hours: 2.77, gps_verified: true },
      { worker_id: 501, worker_name: "Ana Reyes",   event_id: 7003, date: "2026-09-08", hours: 3.97, gps_verified: true },
      { worker_id: 502, worker_name: "Luis Ortega", event_id: 7004, date: "2026-09-08", hours: 2.15, gps_verified: true },
      { worker_id: 501, worker_name: "Ana Reyes",   event_id: 7002, date: "2026-09-09", hours: 2.28, gps_verified: true },
      { worker_id: 501, worker_name: "Ana Reyes",   event_id: 7002, date: "2026-09-11", hours: 2.42, gps_verified: true },
      { worker_id: 501, worker_name: "Ana Reyes",   event_id: 7001, date: "2026-09-11", hours: 2.80, gps_verified: true }
    ],
    summary_hours_per_worker: { 501: { worker_name: "Ana Reyes", hours: 14.24, days: 4 }, 502: { worker_name: "Luis Ortega", hours: 2.15, days: 1 } }
(free)

shift_status: shift_id 88001
  → status "checked_out", actual_in "2026-09-07T11:26:10-07:00", actual_out "2026-09-07T14:12:05-07:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 38 }, { type: "out", gps_verified: true, distance_from_site_m: 35 } ]
(free; repeated for 88002–88006 for exact stamps)
```

Agent (metered read, rule 9):

> There are 6 Turnover Reports to pull. Each has photos, so they're $0.15 apiece, $0.90 total. I'll read them once and keep the summaries and photo links locally. OK?

Owner: *"go"*

```
form_export:
  form_id: 301
  since: "2026-09-07"
  until: "2026-09-11"
  format: "json"
  → row_count: 6, rows: [
      { submission_id: 3301, worker_id: 501, event_id: 7001, submitted_at: "2026-09-07 14:09:51",
        data: { rooms_done: ["kitchen","living_room","bedroom_1","bedroom_2","bathroom_1","bathroom_2","outdoor___balcony"],
                guest_ready: "yes", damage: "no", left_items: "no", restock: ["toilet_paper","coffee___tea"], linen_sets: 2,
                notes: "Balcony chairs wiped, guest left the AC on 65." },
        media: [ { field: "photos_ready", cdn_url: "https://cdn.zensched.com/m/.../p1a.jpg" }, ... 6 items ] },
      { submission_id: 3302, worker_id: 501, event_id: 7003, submitted_at: "2026-09-08 15:19:30",
        data: { rooms_done: ["kitchen","living_room","bedroom_1","bedroom_2","bedroom_3","bathroom_1","bathroom_2","outdoor___balcony","laundry"],
                guest_ready: "yes", damage: "yes",
                damage_notes: "Cracked floor tile by the shower drain in bathroom 1, sharp edge, taped it over for now",
                left_items: "no", restock: ["none"], linen_sets: 3 },
        media: [ ... 6 photos_ready ..., { field: "damage_photos", cdn_url: "https://cdn.zensched.com/m/.../d1.jpg" }, { field: "damage_photos", cdn_url: ".../d2.jpg" } ] },
      { submission_id: 3303, worker_id: 502, event_id: 7004, submitted_at: "2026-09-08 12:35:02",
        data: { rooms_done: ["kitchen","living_room","bedroom_1","bathroom_1"], guest_ready: "yes", damage: "no", left_items: "no",
                restock: ["paper_towels"], linen_sets: 1 }, media: [ ... 4 photos_ready ... ] },
      { submission_id: 3304, worker_id: 501, event_id: 7002, submitted_at: "2026-09-09 12:45:18",
        data: { rooms_done: ["kitchen","living_room","bedroom_1","bathroom_1"], guest_ready: "yes", damage: "no",
                left_items: "yes", left_items_notes: "White phone charger and a paperback on the nightstand, both in the kitchen drawer",
                restock: ["trash_bags","dish_soap"], linen_sets: 1 }, media: [ ... ] },
      { submission_id: 3305, ... event_id 7002, 2026-09-11 11:50 ... restock: ["none"], linen_sets: 1 ... },
      { submission_id: 3306, ... event_id 7001, 2026-09-11 15:02 ... restock: ["dishwasher_pods"], linen_sets: 2 ... }
    ]
    billing: { meter: "form_media", units: 6, price: 0.90 }

sqlite_execute:
  UPDATE turnovers
  SET status = 'completed', checkin_at = '2026-09-07T11:26:10-07:00', checkout_at = '2026-09-07T14:12:05-07:00', gps_verified = 1,
      report_dc_id = 3301,
      rooms_done = '["kitchen","living_room","bedroom_1","bedroom_2","bathroom_1","bathroom_2","outdoor___balcony"]',
      guest_ready = 1,
      photo_urls = '["https://cdn.zensched.com/m/.../p1a.jpg", ... ]',
      damage_flag = 0, left_items = 0,
      restock_json = '["toilet_paper","coffee___tea"]', linen_sets_used = 2,
      report_notes = 'Balcony chairs wiped, guest left the AC on 65.'
  WHERE turnover_id = 1;

sqlite_execute:
  UPDATE turnovers
  SET status = 'completed', checkin_at = '2026-09-08T11:24:22-07:00', checkout_at = '2026-09-08T15:22:40-07:00', gps_verified = 1,
      report_dc_id = 3302, rooms_done = '[...9 rooms...]', guest_ready = 1, photo_urls = '[...6...]',
      damage_flag = 1, damage_notes = 'Cracked floor tile by the shower drain in bathroom 1, sharp edge, taped it over for now',
      damage_photo_urls = '["https://cdn.zensched.com/m/.../d1.jpg","https://cdn.zensched.com/m/.../d2.jpg"]',
      left_items = 0, restock_json = '["none"]', linen_sets_used = 3
  WHERE turnover_id = 3;

sqlite_execute: UPDATE turnovers SET status = 'completed', checkin_at = '2026-09-08T10:28:05-06:00', checkout_at = '2026-09-08T12:37:11-06:00', gps_verified = 1,
      report_dc_id = 3303, ..., restock_json = '["paper_towels"]', linen_sets_used = 1 WHERE turnover_id = 4;

sqlite_execute: UPDATE turnovers SET status = 'completed', checkin_at = '2026-09-09T10:31:00-07:00', checkout_at = '2026-09-09T12:48:12-07:00', gps_verified = 1,
      report_dc_id = 3304, ..., left_items = 1,
      left_items_notes = 'White phone charger and a paperback on the nightstand, both in the kitchen drawer',
      restock_json = '["trash_bags","dish_soap"]', linen_sets_used = 1 WHERE turnover_id = 2;

sqlite_execute: UPDATE turnovers SET status = 'completed', ... report_dc_id = 3305, restock_json = '["none"]', linen_sets_used = 1 WHERE turnover_id = 6;
sqlite_execute: UPDATE turnovers SET status = 'completed', checkin_at = '2026-09-11T12:16:40-07:00', checkout_at = '2026-09-11T15:04:33-07:00', gps_verified = 1,
      report_dc_id = 3306, restock_json = '["dishwasher_pods"]', linen_sets_used = 2, ... WHERE turnover_id = 5;
```

> Recorded 6 turnovers, all GPS-verified in and out, all marked guest-ready.
>
> **Damage — Beach House, Tuesday.** Ana wrote: *"Cracked floor tile by the shower drain in bathroom 1, sharp edge, taped it over for now."* Two photos: [d1.jpg] [d2.jpg]. Marisol should know before the next guest; want me to draft a message?
>
> **Left items — Casita, Wednesday.** White phone charger and a paperback, now in the kitchen drawer. Marisol may want to message that guest.
>
> Restock list has 4 lines (say "restock list"). Ana's Friday Palm St turnover finished 15:04, 56 minutes before the guest. Linen used this week: Palm St 4 sets, Beach House 3, Casita 2, Loft 1.

## "Is Palm 12B ready?"

```
sqlite_query:
  SELECT t.turnover_date, t.status, t.checkin_at, t.checkout_at, t.gps_verified, t.guest_ready, t.photo_urls, t.damage_flag, t.report_notes, c.name
  FROM turnovers t JOIN units u ON u.unit_id = t.unit_id LEFT JOIN cleaners c ON c.cleaner_id = t.cleaner_id
  WHERE u.label LIKE 'Palm St%' ORDER BY t.turnover_date DESC LIMIT 1;
  → 2026-09-11 | completed | 12:16:40 | 15:04:33 | 1 | 1 | [6 urls] | 0 | NULL | Ana Reyes
```

No ZenSched call, no cost.

> Yes. Ana checked out at 15:04 on Friday, GPS-verified at the building. Guest-ready, 6 photos you can forward to Marisol:
> https://cdn.zensched.com/m/.../p5a.jpg … (6 links)

## "Draft a note to Marisol about the tile, then mark it handled."

```
sqlite_query: SELECT * FROM damage_reports_open;
  → t3 | 2026-09-08 | Marisol Vega | 619-555-0101 | marisol@example.com | Beach House | 880 Ocean Blvd | Ana Reyes
       | "Cracked floor tile by the shower drain..." | [d1.jpg, d2.jpg]
```

> Here's a message for Marisol:
>
> > Hi Marisol — during Tuesday's Beach House turnover Ana found a cracked floor tile by the shower drain in the main bathroom with a sharp edge. She taped it over so it's safe for this guest, but it should be replaced before it chips further. Photos: [d1.jpg] [d2.jpg]. Want us to line up a tiler or will you handle it? — Coastal Turnover Co
>
> Say "sent" and I'll mark it handled.

Owner: *"sent"*

```
sqlite_execute: UPDATE turnovers SET damage_ack = 1 WHERE turnover_id = 3;
```

The cleaner's `damage_flag` and `damage_notes` stay as written; only `damage_ack` changes.

## "Restock list."

```
sqlite_query: SELECT * FROM restock_needed;
  → Marisol Vega | Palm St 12B | 12 Palm Street, San Diego | 2026-09-11 | ["dishwasher_pods"] | linen 2 | Ana Reyes
    Dev Patel    | Loft 4      | 9 Mill Road, Denver      | 2026-09-08 | ["paper_towels"]    | linen 1 | Luis Ortega
  (2 rows)
```

The view takes the **latest** completed report per unit, so Palm St shows Friday's dishwasher pods, not Monday's toilet paper and coffee (the owner presumably restocked between the two), and the Casita drops off because Friday's report said None. The Beach House said None on Tuesday.

> Restock:
> - **Marisol — Palm St 12B:** dishwasher pods (Fri). Monday's report wanted toilet paper and coffee; Friday didn't, so I assume those were topped up.
> - **Dev — Loft 4:** paper towels (Tue).
>
> Nothing for the Casita or Beach House.

## "Invoice everyone."

```
sqlite_query: SELECT * FROM turnovers_to_invoice;
  → Marisol Vega | marisol@example.com | terms 14 | 5 turnovers | 730.00 | 2026-09-07 .. 2026-09-11 | missing_price 0
    Dev Patel    | dev@example.com     | terms 7  | 1 turnover  | 110.00 | 2026-09-08 .. 2026-09-08 | missing_price 0

sqlite_execute:
  INSERT INTO invoices (host_id, invoice_date, due_date, turnover_count, total_amount, line_items)
  SELECT h.host_id, date('now'),
         date('now', '+' || COALESCE(h.payment_terms_days, (SELECT value FROM settings WHERE key = 'invoice_due_days')) || ' days'),
         COUNT(t.turnover_id), SUM(t.host_amount),
         json_group_array(json_object('turnover_id', t.turnover_id, 'date', t.turnover_date, 'unit', u.label, 'type', t.turnover_type,
                                      'amount', t.host_amount, 'shift_id', t.zensched_shift_id))
  FROM turnovers t JOIN units u ON u.unit_id = t.unit_id JOIN hosts h ON h.host_id = u.host_id
  WHERE t.status = 'completed' AND t.host_invoiced = 0 AND h.host_id = 1 GROUP BY h.host_id;

sqlite_execute: UPDATE turnovers SET host_invoiced = 1 WHERE status = 'completed' AND host_invoiced = 0 AND unit_id IN (SELECT unit_id FROM units WHERE host_id = 1);
sqlite_query:   SELECT invoice_number, invoice_date, due_date, turnover_count, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-12 | 2026-09-26 | 5 | 730.00     (number assigned by trigger; 14-day terms)

(same for host 2 → INV-2026-0002 | 2026-09-12 | 2026-09-19 | 1 | 110.00, 7-day default)
```

> Two invoices, ready to paste:
>
> ```
> Coastal Turnover Co
> Invoice INV-2026-0001
> To: Marisol Vega (marisol@example.com)
> Date: Sep 12, 2026    Due: Sep 26, 2026 (net 14)
>
>   Mon Sep 7    Palm St 12B    Turnover, Ana     $140.00
>   Tue Sep 8    Beach House    Turnover, Ana     $210.00
>   Wed Sep 9    Casita         Turnover, Ana     $120.00
>   Fri Sep 11   Casita         Turnover, Ana     $120.00
>   Fri Sep 11   Palm St 12B    Turnover, Ana     $140.00
>
> 5 turnovers.  Total due: $730.00
> Every turnover was GPS-verified at the unit; guest-ready photo reports available on request.
> ```
>
> ```
> Coastal Turnover Co
> Invoice INV-2026-0002
> To: Dev Patel (dev@example.com)
> Date: Sep 12, 2026    Due: Sep 19, 2026 (net 7)
>
>   Tue Sep 8    Loft 4    Turnover, Luis    $110.00
>
> 1 turnover.  Total due: $110.00
> Every turnover was GPS-verified at the unit; guest-ready photo report available on request.
> ```
>
> Say "sent" when they're out and I'll note the dates.

Nothing on either invoice mentions codes, wifi, or what the cleaners are paid.

## "Pay run."

```
sqlite_query: SELECT * FROM cleaner_pay_due;
  → Ana Reyes   | worker 501 | per_turnover | use_timesheet_export 0 | 5 turnovers | amount_due 365.00 | missing_pay 0 | 2026-09-07..2026-09-11 | [1,3,2,6,5]
    Luis Ortega | worker 502 | hourly 22.50 | use_timesheet_export 1 | 1 turnover  | amount_due NULL   | ...                | 2026-09-08..2026-09-08 | [4]
```

Ana's total is the sum of the per-unit snapshots: $70 + $105 + $60 + $60 + $70. Luis is hourly, so the agent uses the free hours export already pulled this session (2.15 verified hours on Sep 8).

> Pay run for Sep 7–11:
>
> ```
> Ana Reyes     5 turnovers                        $365.00
>               (Palm St 12B x2 $70, Casita x2 $60, Beach House $105)
>               14.24 GPS-verified hours, about $25.60/h effective
> Luis Ortega   2.15 h  x  $22.50                  $48.38
>               (Loft 4, Tue, GPS-verified in and out)
> Total                                             $413.38
> ```
>
> If you'd like ZenSched to apply break and overtime rules to Luis's hours and give you a CSV, I can run the processed timesheet ($0.10) once you tell me your pay week. Say "paid" and I'll record it.

Owner: *"paid"*

```
sqlite_execute: INSERT INTO cleaner_payouts (cleaner_id, period_start, period_end, turnover_count, amount, turnover_ids) VALUES (1, '2026-09-07', '2026-09-11', 5, 365.00, '[1,3,2,6,5]');
sqlite_execute: UPDATE cleaner_payouts SET paid = 1, paid_date = date('now') WHERE payout_id = last_insert_rowid();
sqlite_execute: INSERT INTO cleaner_payouts (cleaner_id, period_start, period_end, turnover_count, hours, amount, turnover_ids) VALUES (2, '2026-09-07', '2026-09-11', 1, 2.15, 48.38, '[4]');
sqlite_execute: UPDATE cleaner_payouts SET paid = 1, paid_date = date('now') WHERE payout_id = last_insert_rowid();
sqlite_execute: UPDATE turnovers SET cleaner_paid = 1 WHERE status = 'completed' AND cleaner_paid = 0 AND turnover_date BETWEEN '2026-09-07' AND '2026-09-11';
```

## "Marisol paid the first invoice."

```
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
sqlite_query:   SELECT * FROM invoices_outstanding;
  → INV-2026-0002 | Dev Patel | due 2026-09-19 | 110.00 | days_outstanding 0 | overdue 0 | current
```

> Marked INV-2026-0001 paid. Only Dev's $110 is open, due Sep 19.

## "Dev wants a quick inspection of the loft every Sunday at 10, one hour, $40. Luis."

```
sqlite_execute:
  INSERT INTO recurring_cleans (unit_id, weekdays, start_time, duration_minutes, turnover_type, preferred_cleaner_id, start_date, notes)
  VALUES (4, '0000001', '10:00', 60, 'inspection', 2, '2026-09-13', 'Weekly inspection, $40 flat');   → 1

sqlite_query: SELECT * FROM recurring_due_this_week;
  → 2026-09-13 | rec 1 | inspection | Loft 4 | Dev Patel - Loft 4 | -06:00 | 10:00 | 60 min
               | start_iso 2026-09-13T10:00:00-06:00 | end_iso 2026-09-13T11:00:00-06:00
               | Luis Ortega (502) | unassigned 0 | evt 7004 | needs_event_roll 0

sqlite_execute:
  INSERT INTO turnovers (unit_id, recurring_id, turnover_date, scheduled_start, scheduled_end, turnover_type, cleaner_id, host_amount, cleaner_amount)
  VALUES (4, 1, '2026-09-13', '2026-09-13T10:00:00-06:00', '2026-09-13T11:00:00-06:00', 'inspection', 2, 40.00, NULL);   → 7

shift_create: event_id 7004, worker_id 502, start "2026-09-13T10:00:00-06:00", end "2026-09-13T11:00:00-06:00", idempotency_key "shift-turnover-7"  → 88007
sqlite_execute: UPDATE turnovers SET zensched_shift_id = 88007, zensched_event_id = 7004, status = 'assigned' WHERE turnover_id = 7;
```

`host_amount` is passed explicitly ($40, not the unit's $110 turnover price). `cleaner_amount` is left NULL because Luis is hourly; the pay view ignores it and uses his verified time. Running "expand recurring" next week produces the following Sunday and skips this one.

> Added a weekly Sunday 10:00 inspection at Loft 4 for Luis and dispatched this Sunday's. It bills Dev $40 and pays Luis his hourly rate for the verified time.

## Late October: "Load next week's checkouts" (event roll)

```
sqlite_query: SELECT * FROM turnovers_upcoming WHERE needs_shift = 1;
  → 2026-11-02 | t41 | Palm St 12B | event_valid_until 2026-11-03 | needs_event_roll 0 | ...
    2026-11-04 | t42 | Casita      | event_valid_until 2026-11-03 | needs_event_roll 1 | ...
    2026-11-05 | t43 | Loft 4      | event_valid_until 2026-11-03 | needs_event_roll 1 | ...

event_create:
  location_id: 9002
  title: "Turnovers - Marisol Vega - Casita"
  start_date: "2026-11-04"
  end_date:   "2027-01-02"
  idempotency_key: "event-unit-2-20261104"
  → event_id: 7140
form_assign:    form_id 301, event_id 7140, idempotency_key "assign-report-7140"
sqlite_execute: UPDATE units SET zensched_event_id = 7140, event_valid_until = '2027-01-02' WHERE unit_id = 2;

event_create: location_id 9004, title "Turnovers - Dev Patel - Loft 4", start_date "2026-11-05", end_date "2027-01-03", idempotency_key "event-unit-4-20261105"  → 7141
form_assign:  form_id 301, event_id 7141, idempotency_key "assign-report-7141"
sqlite_execute: UPDATE units SET zensched_event_id = 7141, event_valid_until = '2027-01-03' WHERE unit_id = 4;

shift_create: event_id 7001 for t41 (old Palm St event still covers Nov 2)
shift_create: event_id 7140 for t42, key "shift-turnover-42"
shift_create: event_id 7141 for t43, key "shift-turnover-43"
```

> Dispatched next week. The Casita and Loft 4 ZenSched events were about to expire (Nov 3), so I renewed them through early January. Palm St 12B's and the Beach House's expire Nov 3 too; I'll renew them when their next turnovers land. Nothing changes for Ana or Luis.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Lobby, lockbox, keypad, alarm, smart-lock and closet codes; wifi passwords | SQLite **only** (`units.access_notes`, `supplies_closet_notes`) | Privacy; never sent to ZenSched |
| Marisol's and Dev's contact details, billing emails, payment terms, platform notes | SQLite | Billing; ZenSched does not model hosts |
| Per-unit host price and cleaner pay; per-unit turnover length and time zone | SQLite | Money and scheduling defaults; ZenSched has neither |
| Ana's per-turnover pay type; Luis's $22.50 hourly rate | SQLite | Pay run; ZenSched holds only the worker account |
| This week's six checkouts and check-ins, the Thursday→Friday extension, the Sunday inspection template | SQLite (`turnovers`, `recurring_cleans`) | The dispatch board; ZenSched does not know about guests or bookings |
| "Marisol Vega - Palm St 12B" and the street address, GPS pin | ZenSched (ID in `units`) | Needed for geofenced check-in |
| The 150 m check-in radius and 15-minute check-out reminder | ZenSched policy 0 | Enforced on every unit; not per location |
| Each unit's current ≤60-day event and its end date | ZenSched (ID + `event_valid_until` in `units`) | Shifts hang off events; renewed by the agent |
| The Turnover Report form | ZenSched (ID in `settings`) | Installed on the cleaner's phone per shift |
| Ana, Luis, their invites, their apps | ZenSched (IDs in `cleaners`) | Workforce and notifications |
| The week's six shifts, the moved shift, the Sunday inspection shift | ZenSched (shift IDs in `turnovers`) | Live schedule; times copied, never the schedule itself |
| GPS punches, actual in/out times, distance from the pin | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export`, stamps copied to `turnovers` |
| Six Turnover Reports and their photos | ZenSched (originals); summary, flags, restock keys, linen counts, and photo URLs in `turnovers` | Read once (metered), then answered from SQLite for free |
| Two host invoices, two cleaner payouts, `host_invoiced` / `cleaner_paid` flags | SQLite | Money |
