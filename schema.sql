-- ZenSched Short-Term-Rental Turnover Local Database Schema
-- SQLite database for hosts, units, cleaner roster, booking-driven turnovers,
-- optional recurring cleans, Turnover Report summaries, host invoicing, and
-- cleaner pay runs.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my turnover-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 turnover-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- PRIVACY: units.access_notes (lockbox and door codes, wifi password, alarm
-- code, host's personal phone) and units.supplies_closet_notes (closet code)
-- live ONLY in this file on your computer. They are never sent to ZenSched.
-- SKILL.md forbids the agent from putting them in any ZenSched field
-- (location name or notes, event title or notes, shift cancel reason, form).
-- ZenSched receives, per unit, a short name ("Marisol - Palm St 12B"), the
-- street address for the GPS pin, and the Turnover Report the cleaner fills in.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, defaults, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Turnover Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '7');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('turnover_form_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_turnover_minutes', '180');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_start_offset_minutes', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('event_window_days', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '75');

-- Hosts: the Airbnb / VRBO owners or property managers you bill. One host can
-- own many units. payment_terms_days NULL = settings.invoice_due_days.
CREATE TABLE IF NOT EXISTS hosts (
  host_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  contact TEXT,                                     -- phone or preferred channel
  billing_email TEXT,
  payment_terms_days INTEGER,                       -- NULL = settings.invoice_due_days
  platform_notes TEXT,                              -- 'Airbnb + VRBO via Hospitable', 'sends Turno export Sundays'
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Units: the rental properties, with ZenSched references.
-- One ZenSched LOCATION per unit, created once and kept forever.
-- One ZenSched EVENT per unit per rolling window of at most 60 days
-- (ZenSched caps event length). zensched_event_id is the CURRENT event and
-- event_valid_until is its last valid date. When a turnover date is later than
-- event_valid_until, the agent creates a new event and updates both columns.
-- tz_offset is PER UNIT so a crew serving two markets schedules each unit in
-- its own local time; NULL on insert is filled from settings.timezone_offset.
-- host_price is what the host pays per turnover; cleaner_pay is the flat
-- per-turnover amount for cleaners on pay_type 'per_turnover'. Both are
-- snapshotted onto each turnover row when it is created.
CREATE TABLE IF NOT EXISTS units (
  unit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  host_id INTEGER NOT NULL,
  label TEXT NOT NULL,                              -- 'Palm St 12B', 'Beach House'
  address TEXT NOT NULL,
  city TEXT,
  region TEXT,                                      -- state / province
  country TEXT,
  postal TEXT,
  tz_offset TEXT                                    -- '-07:00'; NULL = settings.timezone_offset (trigger fills)
    CHECK (tz_offset IS NULL OR tz_offset GLOB '[+-][0-1][0-9]:[0-5][0-9]'),
  bedrooms INTEGER,
  bathrooms REAL,
  turnover_minutes INTEGER                          -- NULL = settings.default_turnover_minutes
    CHECK (turnover_minutes IS NULL OR turnover_minutes BETWEEN 30 AND 1440),
  host_price REAL,                                  -- $ the host pays per turnover
  cleaner_pay REAL,                                 -- $ flat per turnover for per_turnover cleaners
  access_notes TEXT,                                -- LOCAL ONLY: lockbox / door code, wifi, alarm, host phone
  supplies_closet_notes TEXT,                       -- LOCAL ONLY: where the closet is, its code, what is kept there
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  zensched_event_id INTEGER,                        -- from event_create (current <=60-day window)
  event_valid_until TEXT,                           -- ISO date: last day the current event covers
  is_active INTEGER DEFAULT 1,                      -- 0 = host delisted / paused
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (host_id) REFERENCES hosts(host_id) ON DELETE CASCADE
);

-- Cleaners: your roster. zensched_worker_id comes from worker_invite.
-- pay_type 'per_turnover' = paid units.cleaner_pay per completed turnover;
-- 'hourly' = paid pay_rate per GPS-verified hour from timesheet_export.
CREATE TABLE IF NOT EXISTS cleaners (
  cleaner_id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  pay_type TEXT NOT NULL DEFAULT 'per_turnover'
    CHECK (pay_type IN ('per_turnover', 'hourly')),
  pay_rate REAL,                                    -- $/hour when pay_type = 'hourly'; ignored otherwise
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Recurring cleans: optional template for mid-stay refreshes, deep cleans, or
-- inspections that are NOT tied to a booking ("Beach House: deep clean every
-- Monday 10:00, 4 h"). weekdays is a 7-character mask, Monday first:
-- '1000000' = Mondays. The agent expands this into turnovers rows (and then
-- shifts) once a week using the recurring_due_this_week view.
CREATE TABLE IF NOT EXISTS recurring_cleans (
  recurring_id INTEGER PRIMARY KEY AUTOINCREMENT,
  unit_id INTEGER NOT NULL,
  weekdays TEXT NOT NULL
    CHECK (length(weekdays) = 7 AND weekdays NOT GLOB '*[^01]*'),
  start_time TEXT NOT NULL                          -- 'HH:MM' 24-hour, unit local time
    CHECK (start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  duration_minutes INTEGER NOT NULL DEFAULT 120
    CHECK (duration_minutes BETWEEN 30 AND 1440),
  turnover_type TEXT NOT NULL DEFAULT 'mid_stay'
    CHECK (turnover_type IN ('turnover', 'mid_stay', 'deep_clean', 'inspection')),
  preferred_cleaner_id INTEGER,                     -- local cleaner row; NULL = agent asks
  start_date TEXT,                                  -- first date this applies (NULL = already running)
  end_date TEXT,                                    -- last date (NULL = open-ended)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE,
  FOREIGN KEY (preferred_cleaner_id) REFERENCES cleaners(cleaner_id) ON DELETE SET NULL
);

-- Turnovers: one row per clean, created when the owner loads the week's
-- checkouts (or expands a recurring clean), then updated through its life:
--   open -> assigned (cleaner + shift) -> in_progress (GPS check-in seen)
--        -> completed (checked out + Turnover Report recorded)
--   or missed / cancelled.
-- checkout_time is when the departing guest leaves; checkin_time is when the
-- next guest arrives (both 'HH:MM', unit local time). scheduled_start /
-- scheduled_end are ISO 8601 with the unit's offset and are what shift_create
-- receives; if left NULL the fill_turnover_defaults trigger derives them from
-- checkout_time + settings.default_start_offset_minutes and the unit's
-- turnover_minutes. host_amount and cleaner_amount are snapshots from the unit
-- taken by the same trigger when left NULL, so later price changes never
-- rewrite history. Report columns are copied from the Turnover Report once.
CREATE TABLE IF NOT EXISTS turnovers (
  turnover_id INTEGER PRIMARY KEY AUTOINCREMENT,
  unit_id INTEGER NOT NULL,
  recurring_id INTEGER,                             -- set when expanded from recurring_cleans
  turnover_date TEXT NOT NULL,                      -- ISO date, unit local
  checkout_time TEXT                                -- departing guest, 'HH:MM'
    CHECK (checkout_time IS NULL OR checkout_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  checkin_time TEXT                                 -- arriving guest, 'HH:MM'
    CHECK (checkin_time IS NULL OR checkin_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  scheduled_start TEXT,                             -- ISO datetime with unit offset (trigger fills if NULL)
  scheduled_end TEXT,
  cleaner_id INTEGER,                               -- NULL = unassigned
  turnover_type TEXT NOT NULL DEFAULT 'turnover'
    CHECK (turnover_type IN ('turnover', 'mid_stay', 'deep_clean', 'inspection')),
  zensched_shift_id INTEGER UNIQUE,                 -- from shift_create; prevents double dispatch / double record
  zensched_event_id INTEGER,                        -- event the shift was created on
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'assigned', 'in_progress', 'completed', 'missed', 'cancelled')),
  report_dc_id INTEGER,                             -- Turnover Report submission_id
  checkin_at TEXT,                                  -- cleaner GPS check-in, ISO with offset (from shift_status)
  checkout_at TEXT,                                 -- cleaner GPS check-out
  gps_verified INTEGER,                             -- 1 if both punches were on site
  rooms_done TEXT,                                  -- JSON array of option keys
  guest_ready INTEGER,                              -- 1 = form said Yes, 0 = 'No - see notes'
  photo_urls TEXT,                                  -- JSON array of guest-ready photo URLs (host proof)
  damage_flag INTEGER DEFAULT 0,
  damage_notes TEXT,
  damage_photo_urls TEXT,                           -- JSON array
  damage_ack INTEGER DEFAULT 0,                     -- 1 once the owner has told the host / dealt with it
  left_items INTEGER DEFAULT 0,
  left_items_notes TEXT,
  restock_json TEXT,                                -- JSON array of option keys from 'Needs restocking'
  linen_sets_used INTEGER,
  report_notes TEXT,                                -- 'Notes for the host / office'
  host_amount REAL,                                 -- snapshot of units.host_price (trigger fills if NULL)
  cleaner_amount REAL,                              -- snapshot of units.cleaner_pay (trigger fills if NULL)
  host_invoiced INTEGER DEFAULT 0,
  cleaner_paid INTEGER DEFAULT 0,
  notes TEXT,                                       -- owner / dispatch notes ('guest asked for late checkout')
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (unit_id) REFERENCES units(unit_id) ON DELETE CASCADE,
  FOREIGN KEY (recurring_id) REFERENCES recurring_cleans(recurring_id) ON DELETE SET NULL,
  FOREIGN KEY (cleaner_id) REFERENCES cleaners(cleaner_id) ON DELETE SET NULL
);

-- Invoices: billed to hosts. invoice_number is filled in by a trigger if NULL.
-- line_items is a JSON array with one object per turnover.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  host_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  turnover_count INTEGER,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed it
  line_items TEXT,                                  -- JSON array: turnover_id, date, unit, type, amount, shift_id
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (host_id) REFERENCES hosts(host_id) ON DELETE CASCADE
);

-- Cleaner payouts: one row per cleaner per pay run. amount is the sum of
-- per-turnover snapshots, or hours * pay_rate for hourly cleaners (hours from
-- timesheet_export). turnover_ids is a JSON array of the turnovers covered.
CREATE TABLE IF NOT EXISTS cleaner_payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  cleaner_id INTEGER NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  turnover_count INTEGER,
  hours REAL,                                       -- hourly cleaners only
  amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  turnover_ids TEXT,                                -- JSON array of turnover_id
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (cleaner_id) REFERENCES cleaners(cleaner_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_units_host ON units(host_id, is_active);
CREATE INDEX IF NOT EXISTS idx_units_zensched_event ON units(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_units_zensched_location ON units(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_recurring_unit ON recurring_cleans(unit_id, is_active);
CREATE INDEX IF NOT EXISTS idx_turnovers_unit_date ON turnovers(unit_id, turnover_date);
CREATE INDEX IF NOT EXISTS idx_turnovers_date_status ON turnovers(turnover_date, status);
CREATE INDEX IF NOT EXISTS idx_turnovers_cleaner ON turnovers(cleaner_id, cleaner_paid);
CREATE INDEX IF NOT EXISTS idx_turnovers_invoiced ON turnovers(host_invoiced, status);
CREATE INDEX IF NOT EXISTS idx_turnovers_recurring ON turnovers(recurring_id, turnover_date);
CREATE INDEX IF NOT EXISTS idx_turnovers_damage ON turnovers(damage_flag, damage_ack);
CREATE INDEX IF NOT EXISTS idx_invoices_host ON invoices(host_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);
CREATE INDEX IF NOT EXISTS idx_payouts_cleaner ON cleaner_payouts(cleaner_id, paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_host_timestamp
AFTER UPDATE ON hosts
BEGIN
  UPDATE hosts SET updated_at = datetime('now') WHERE host_id = NEW.host_id;
END;

CREATE TRIGGER IF NOT EXISTS update_unit_timestamp
AFTER UPDATE ON units
BEGIN
  UPDATE units SET updated_at = datetime('now') WHERE unit_id = NEW.unit_id;
END;

CREATE TRIGGER IF NOT EXISTS update_cleaner_timestamp
AFTER UPDATE ON cleaners
BEGIN
  UPDATE cleaners SET updated_at = datetime('now') WHERE cleaner_id = NEW.cleaner_id;
END;

CREATE TRIGGER IF NOT EXISTS update_recurring_timestamp
AFTER UPDATE ON recurring_cleans
BEGIN
  UPDATE recurring_cleans SET updated_at = datetime('now') WHERE recurring_id = NEW.recurring_id;
END;

CREATE TRIGGER IF NOT EXISTS update_turnover_timestamp
AFTER UPDATE ON turnovers
BEGIN
  UPDATE turnovers SET updated_at = datetime('now') WHERE turnover_id = NEW.turnover_id;
END;

-- New units inherit the business timezone when none is given.
CREATE TRIGGER IF NOT EXISTS fill_unit_defaults
AFTER INSERT ON units
WHEN NEW.tz_offset IS NULL
BEGIN
  UPDATE units
  SET tz_offset = (SELECT value FROM settings WHERE key = 'timezone_offset')
  WHERE unit_id = NEW.unit_id;
END;

-- Fill derived turnover columns when the agent leaves them NULL:
--   scheduled_start <- turnover_date + checkout_time + default_start_offset_minutes, in the unit's offset
--   scheduled_end   <- scheduled_start + units.turnover_minutes (else settings.default_turnover_minutes)
--   host_amount     <- units.host_price
--   cleaner_amount  <- units.cleaner_pay
-- The offset is stripped (substr 1..19) before adding minutes and re-appended
-- afterwards, because SQLite's datetime() would otherwise convert to UTC.
-- If checkout_time is NULL (mid-stay / deep clean) and scheduled_start is NULL,
-- scheduled_start stays NULL and the agent must supply it.
CREATE TRIGGER IF NOT EXISTS fill_turnover_defaults
AFTER INSERT ON turnovers
BEGIN
  UPDATE turnovers
  SET scheduled_start = COALESCE(NEW.scheduled_start,
        CASE WHEN NEW.checkout_time IS NOT NULL THEN
          strftime('%Y-%m-%dT%H:%M:%S',
                   datetime(NEW.turnover_date || ' ' || NEW.checkout_time || ':00',
                            '+' || (SELECT value FROM settings WHERE key = 'default_start_offset_minutes') || ' minutes'))
          || (SELECT tz_offset FROM units WHERE unit_id = NEW.unit_id)
        END),
      host_amount = COALESCE(NEW.host_amount, (SELECT host_price FROM units WHERE unit_id = NEW.unit_id)),
      cleaner_amount = COALESCE(NEW.cleaner_amount, (SELECT cleaner_pay FROM units WHERE unit_id = NEW.unit_id))
  WHERE turnover_id = NEW.turnover_id;
  UPDATE turnovers
  SET scheduled_end = COALESCE(NEW.scheduled_end,
        CASE WHEN scheduled_start IS NOT NULL THEN
          strftime('%Y-%m-%dT%H:%M:%S',
                   datetime(substr(scheduled_start, 1, 19),
                            '+' || COALESCE((SELECT turnover_minutes FROM units WHERE unit_id = NEW.unit_id),
                                            (SELECT value FROM settings WHERE key = 'default_turnover_minutes')) || ' minutes'))
          || (SELECT tz_offset FROM units WHERE unit_id = NEW.unit_id)
        END)
  WHERE turnover_id = NEW.turnover_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- The dispatch board: every non-cancelled turnover joined to its unit, host,
-- and cleaner, with everything the agent needs to create or check a shift.
--   local_today      today's date IN THE UNIT'S TIMEZONE (so a 5 pm Pacific
--                    session does not think it is tomorrow)
--   start_iso/end_iso ready for shift_create (unit offset, never Z)
--   slack_minutes    minutes between scheduled_end and the next guest's
--                    check-in (NULL when no check-in time); tight_slack < 30
--   needs_location   unit has no ZenSched location yet
--   needs_event_roll unit's event does not cover turnover_date
--   unassigned       no cleaner
--   needs_shift      no shift created yet
--   idempotency_key  for shift_create
-- turnovers_today / turnovers_upcoming / turnovers_unassigned / turnovers_at_risk
-- are filters over this view.
CREATE VIEW IF NOT EXISTS turnover_board AS
SELECT
  t.turnover_id,
  t.turnover_date,
  t.turnover_type,
  t.status,
  u.unit_id,
  u.label                                    AS unit_label,
  h.host_id,
  h.name                                     AS host_name,
  h.name || ' - ' || u.label                 AS zensched_name,
  u.address,
  u.city,
  u.tz_offset,
  date('now', (CASE WHEN substr(u.tz_offset, 1, 1) = '-' THEN '-' ELSE '+' END)
              || (CAST(substr(u.tz_offset, 2, 2) AS INTEGER) * 60 + CAST(substr(u.tz_offset, 5, 2) AS INTEGER))
              || ' minutes')                 AS local_today,
  t.checkout_time,
  t.checkin_time,
  t.scheduled_start                          AS start_iso,
  t.scheduled_end                            AS end_iso,
  CASE WHEN t.checkin_time IS NOT NULL AND t.scheduled_end IS NOT NULL
       THEN CAST(round((julianday(t.turnover_date || 'T' || t.checkin_time || ':00' || u.tz_offset)
                        - julianday(t.scheduled_end)) * 1440) AS INTEGER) END AS slack_minutes,
  CASE WHEN t.checkin_time IS NOT NULL AND t.scheduled_end IS NOT NULL
        AND round((julianday(t.turnover_date || 'T' || t.checkin_time || ':00' || u.tz_offset)
                   - julianday(t.scheduled_end)) * 1440) < 30 THEN 1 ELSE 0 END AS tight_slack,
  t.cleaner_id,
  c.name                                     AS cleaner_name,
  c.zensched_worker_id                       AS worker_id,
  CASE WHEN t.cleaner_id IS NULL THEN 1 ELSE 0 END AS unassigned,
  u.zensched_location_id,
  u.zensched_event_id,
  u.event_valid_until,
  CASE WHEN u.zensched_location_id IS NULL THEN 1 ELSE 0 END AS needs_location,
  CASE WHEN u.event_valid_until IS NULL OR u.event_valid_until < t.turnover_date THEN 1 ELSE 0 END AS needs_event_roll,
  t.zensched_shift_id,
  CASE WHEN t.zensched_shift_id IS NULL THEN 1 ELSE 0 END AS needs_shift,
  'shift-turnover-' || t.turnover_id         AS idempotency_key,
  t.checkin_at,
  t.checkout_at,
  t.host_amount,
  t.cleaner_amount,
  t.notes
FROM turnovers t
JOIN units u ON u.unit_id = t.unit_id
JOIN hosts h ON h.host_id = u.host_id
LEFT JOIN cleaners c ON c.cleaner_id = t.cleaner_id
WHERE t.status <> 'cancelled';

-- Today's turnovers (in each unit's local date), not cancelled, in start order.
CREATE VIEW IF NOT EXISTS turnovers_today AS
SELECT * FROM turnover_board
WHERE turnover_date = local_today
ORDER BY start_iso, host_name, unit_label;

-- Next 7 days (today + 6, unit local), not completed or cancelled. One row per
-- shift the agent may still need to create, roll an event for, or assign.
CREATE VIEW IF NOT EXISTS turnovers_upcoming AS
SELECT * FROM turnover_board
WHERE turnover_date BETWEEN local_today AND date(local_today, '+6 days')
  AND status NOT IN ('completed', 'missed')
ORDER BY turnover_date, start_iso, host_name, unit_label;

-- Upcoming turnovers with no cleaner. The agent must ask, not guess.
CREATE VIEW IF NOT EXISTS turnovers_unassigned AS
SELECT * FROM turnover_board
WHERE cleaner_id IS NULL
  AND status = 'open'
  AND turnover_date >= local_today
ORDER BY turnover_date, start_iso;

-- Today's turnovers that need attention right now:
--   not_checked_in  scheduled_start + 15 min has passed and no GPS check-in recorded
--   tight_slack     scheduled_end is within 60 min of the next guest's check-in
--   unassigned      nobody is dispatched
-- The agent checks shift_status on each and updates checkin_at / status.
CREATE VIEW IF NOT EXISTS turnovers_at_risk AS
SELECT
  b.*,
  CASE
    WHEN b.cleaner_id IS NULL THEN 'unassigned'
    WHEN b.checkin_at IS NULL AND b.start_iso IS NOT NULL
         AND julianday('now') > julianday(b.start_iso) + 15.0 / 1440 THEN 'not_checked_in'
    ELSE 'tight_slack'
  END AS risk
FROM turnover_board b
WHERE b.turnover_date = b.local_today
  AND b.status IN ('open', 'assigned', 'in_progress')
  AND (
       b.cleaner_id IS NULL
    OR (b.checkin_at IS NULL AND b.start_iso IS NOT NULL
        AND julianday('now') > julianday(b.start_iso) + 15.0 / 1440)
    OR (b.slack_minutes IS NOT NULL AND b.slack_minutes < 60)
  )
ORDER BY b.start_iso;

-- Recurring cleans due in the next 7 days (today + 6), expanded from
-- recurring_cleans, minus dates that already have a turnovers row for that
-- template. One row = one INSERT INTO turnovers (then one shift_create).
-- start_iso / end_iso use the unit's offset and are ready to pass as
-- scheduled_start / scheduled_end.
CREATE VIEW IF NOT EXISTS recurring_due_this_week AS
WITH RECURSIVE days(d) AS (
  SELECT date('now')
  UNION ALL
  SELECT date(d, '+1 day') FROM days WHERE d < date('now', '+6 days')
)
SELECT
  days.d                                     AS turnover_date,
  r.recurring_id,
  r.turnover_type,
  u.unit_id,
  u.label                                    AS unit_label,
  h.host_id,
  h.name                                     AS host_name,
  h.name || ' - ' || u.label                 AS zensched_name,
  u.tz_offset,
  r.start_time,
  r.duration_minutes,
  days.d || 'T' || r.start_time || ':00' || u.tz_offset AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(days.d || ' ' || r.start_time || ':00', '+' || r.duration_minutes || ' minutes'))
    || u.tz_offset                           AS end_iso,
  r.preferred_cleaner_id                     AS cleaner_id,
  c.name                                     AS cleaner_name,
  c.zensched_worker_id                       AS worker_id,
  CASE WHEN r.preferred_cleaner_id IS NULL THEN 1 ELSE 0 END AS unassigned,
  u.zensched_location_id,
  u.zensched_event_id,
  u.event_valid_until,
  CASE WHEN u.zensched_location_id IS NULL THEN 1 ELSE 0 END AS needs_location,
  CASE WHEN u.event_valid_until IS NULL OR u.event_valid_until < days.d THEN 1 ELSE 0 END AS needs_event_roll,
  r.notes                                    AS recurring_notes
FROM days
JOIN recurring_cleans r
  ON r.is_active = 1
 AND substr(r.weekdays, CASE strftime('%w', days.d) WHEN '0' THEN 7 ELSE CAST(strftime('%w', days.d) AS INTEGER) END, 1) = '1'
 AND (r.start_date IS NULL OR r.start_date <= days.d)
 AND (r.end_date IS NULL OR r.end_date >= days.d)
JOIN units u ON u.unit_id = r.unit_id AND u.is_active = 1
JOIN hosts h ON h.host_id = u.host_id AND h.is_active = 1
LEFT JOIN cleaners c ON c.cleaner_id = r.preferred_cleaner_id
WHERE NOT EXISTS (
  SELECT 1 FROM turnovers t WHERE t.recurring_id = r.recurring_id AND t.turnover_date = days.d
)
ORDER BY days.d, r.start_time, h.name, u.label;

-- Units whose current ZenSched event expires within 14 days (or has none) and
-- that have upcoming work (an open turnover or an active recurring clean).
-- Roll these proactively.
CREATE VIEW IF NOT EXISTS events_expiring AS
SELECT
  u.unit_id,
  h.name                                     AS host_name,
  u.label                                    AS unit_label,
  h.name || ' - ' || u.label                 AS zensched_name,
  u.address,
  u.zensched_location_id,
  u.zensched_event_id,
  u.event_valid_until,
  (SELECT MIN(t.turnover_date) FROM turnovers t
    WHERE t.unit_id = u.unit_id AND t.status IN ('open', 'assigned') AND t.turnover_date >= date('now')) AS next_turnover_date
FROM units u
JOIN hosts h ON h.host_id = u.host_id AND h.is_active = 1
WHERE u.is_active = 1
  AND (u.event_valid_until IS NULL OR u.event_valid_until <= date('now', '+14 days'))
  AND (
       EXISTS (SELECT 1 FROM turnovers t WHERE t.unit_id = u.unit_id AND t.status IN ('open', 'assigned') AND t.turnover_date >= date('now'))
    OR EXISTS (SELECT 1 FROM recurring_cleans r WHERE r.unit_id = u.unit_id AND r.is_active = 1)
  )
ORDER BY u.event_valid_until;

-- Damage or maintenance reports the owner has not yet acknowledged, newest
-- first, with the host contact to forward them to.
CREATE VIEW IF NOT EXISTS damage_reports_open AS
SELECT
  t.turnover_id,
  t.turnover_date,
  h.host_id,
  h.name                                     AS host_name,
  h.contact                                  AS host_contact,
  h.billing_email                            AS host_email,
  u.unit_id,
  u.label                                    AS unit_label,
  u.address,
  c.name                                     AS cleaner_name,
  t.damage_notes,
  t.damage_photo_urls,
  t.guest_ready,
  t.report_notes,
  t.report_dc_id,
  t.zensched_shift_id
FROM turnovers t
JOIN units u ON u.unit_id = t.unit_id
JOIN hosts h ON h.host_id = u.host_id
LEFT JOIN cleaners c ON c.cleaner_id = t.cleaner_id
WHERE t.damage_flag = 1
  AND t.damage_ack = 0
ORDER BY t.turnover_date DESC, t.turnover_id DESC;

-- The latest completed Turnover Report per unit that asked for restocking.
-- Grouped by host, then city and street, so "what does Marisol need" and
-- "what do I bring to Palm St" are both one query. Excludes reports that
-- ticked only 'None'.
CREATE VIEW IF NOT EXISTS restock_needed AS
SELECT
  h.host_id,
  h.name                                     AS host_name,
  u.unit_id,
  u.label                                    AS unit_label,
  u.address,
  u.city,
  u.supplies_closet_notes,
  t.turnover_id,
  t.turnover_date,
  t.restock_json,
  t.linen_sets_used,
  c.name                                     AS reported_by
FROM turnovers t
JOIN units u ON u.unit_id = t.unit_id
JOIN hosts h ON h.host_id = u.host_id
LEFT JOIN cleaners c ON c.cleaner_id = t.cleaner_id
WHERE t.status = 'completed'
  AND t.turnover_id = (
    SELECT t2.turnover_id FROM turnovers t2
    WHERE t2.unit_id = t.unit_id AND t2.status = 'completed' AND t2.report_dc_id IS NOT NULL
    ORDER BY t2.turnover_date DESC, t2.turnover_id DESC LIMIT 1
  )
  AND t.restock_json IS NOT NULL
  AND trim(t.restock_json) NOT IN ('', '[]', '["none"]')
ORDER BY h.name, u.city, u.address;

-- Completed turnovers not yet on a host invoice, grouped by host, with the
-- billing contact and the host's payment terms (falls back to settings).
CREATE VIEW IF NOT EXISTS turnovers_to_invoice AS
SELECT
  h.host_id,
  h.name                                     AS host_name,
  h.billing_email,
  h.contact,
  COALESCE(h.payment_terms_days, (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'invoice_due_days')) AS terms_days,
  COUNT(t.turnover_id)                       AS turnover_count,
  SUM(t.host_amount)                         AS total_amount,
  MIN(t.turnover_date)                       AS first_turnover_date,
  MAX(t.turnover_date)                       AS last_turnover_date,
  SUM(CASE WHEN t.host_amount IS NULL THEN 1 ELSE 0 END) AS missing_price_count
FROM turnovers t
JOIN units u ON u.unit_id = t.unit_id
JOIN hosts h ON h.host_id = u.host_id
WHERE t.status = 'completed'
  AND t.host_invoiced = 0
GROUP BY h.host_id
ORDER BY h.name;

-- Completed turnovers not yet paid out, per cleaner. For per_turnover cleaners
-- amount_due is the sum of cleaner_amount snapshots. For hourly cleaners
-- amount_due is NULL and use_timesheet_export = 1: the agent runs
-- timesheet_export(mode="hours") for the period and multiplies by pay_rate.
CREATE VIEW IF NOT EXISTS cleaner_pay_due AS
SELECT
  c.cleaner_id,
  c.name                                     AS cleaner_name,
  c.zensched_worker_id,
  c.pay_type,
  c.pay_rate,
  CASE WHEN c.pay_type = 'hourly' THEN 1 ELSE 0 END AS use_timesheet_export,
  COUNT(t.turnover_id)                       AS turnover_count,
  CASE WHEN c.pay_type = 'per_turnover' THEN SUM(t.cleaner_amount) END AS amount_due,
  SUM(CASE WHEN c.pay_type = 'per_turnover' AND t.cleaner_amount IS NULL THEN 1 ELSE 0 END) AS missing_pay_count,
  MIN(t.turnover_date)                       AS first_turnover_date,
  MAX(t.turnover_date)                       AS last_turnover_date,
  json_group_array(t.turnover_id)            AS turnover_ids
FROM turnovers t
JOIN cleaners c ON c.cleaner_id = t.cleaner_id
WHERE t.status = 'completed'
  AND t.cleaner_paid = 0
GROUP BY c.cleaner_id
ORDER BY c.name;

-- Unpaid host invoices with aging, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  h.host_id,
  h.name                                     AS host_name,
  h.billing_email,
  i.invoice_date,
  i.due_date,
  i.turnover_count,
  i.total_amount,
  i.sent_date,
  CAST(julianday('now') - julianday(i.invoice_date) AS INTEGER) AS days_outstanding,
  CASE WHEN i.due_date < date('now') THEN CAST(julianday('now') - julianday(i.due_date) AS INTEGER) ELSE 0 END AS days_overdue,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue,
  CASE
    WHEN i.due_date >= date('now') THEN 'current'
    WHEN julianday('now') - julianday(i.due_date) <= 30 THEN '1-30'
    WHEN julianday('now') - julianday(i.due_date) <= 60 THEN '31-60'
    ELSE '61+'
  END                                        AS aging_bucket
FROM invoices i
JOIN hosts h ON h.host_id = i.host_id
WHERE i.paid = 0
ORDER BY i.due_date;
