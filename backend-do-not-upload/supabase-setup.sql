-- ============================================================
-- SK HomeCare — Supabase Setup v6 (complete, re-runnable)
-- v6: policy cleanup is now limited to this app's tables; security fixes from
--     migration-001-security-fixes.sql are included at the end of this file.
-- SETUP ORDER:
--   1. Supabase Dashboard → Authentication → Users → Add user
--      Email: shaikhayan7744@gmail.com  (set password there)
--      Enable "Auto Confirm User", then DISABLE public sign-ups:
--      Dashboard → Authentication → Providers → Email → disable "Enable Sign-ups"
--   2. Run this entire file in SQL Editor
--   3. Paste your SUPABASE_URL and SUPABASE_ANON_KEY into both HTML files
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ══════════════════════════════════════════════════════════════
-- TABLES
-- ══════════════════════════════════════════════════════════════

-- Admin user allowlist (only listed users can access admin panel)
CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Core content
CREATE TABLE IF NOT EXISTS public.services (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  icon         TEXT NOT NULL DEFAULT '🔧',
  name         TEXT NOT NULL,
  description  TEXT NOT NULL,
  price        TEXT NOT NULL,
  price_prefix TEXT NOT NULL DEFAULT '',
  category     TEXT NOT NULL DEFAULT 'ac',
  sort_order   INTEGER NOT NULL DEFAULT 0,
  active       BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS public.gallery (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  storage_path TEXT NOT NULL,
  public_url   TEXT NOT NULL,
  caption      TEXT NOT NULL DEFAULT '',
  sort_order   INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.faqs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  question    TEXT NOT NULL,
  answer      TEXT NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (question)
);

CREATE TABLE IF NOT EXISTS public.site_content (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT UNIQUE NOT NULL,
  value      TEXT NOT NULL,
  section    TEXT NOT NULL DEFAULT 'general',
  label      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.booking_settings (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT UNIQUE NOT NULL,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.bookings (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL CHECK (length(name) <= 100),
  phone        TEXT NOT NULL CHECK (phone ~ '^\d{10}$'),
  service      TEXT NOT NULL,
  area         TEXT NOT NULL,
  address      TEXT NOT NULL CHECK (length(address) <= 300),
  booking_date DATE NOT NULL,
  booking_time TIME NOT NULL,
  problem      TEXT CHECK (length(coalesce(problem,'')) <= 500),
  status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','confirmed','cancelled','completed')),
  notes        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reviews
CREATE TABLE IF NOT EXISTS public.reviews (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name       TEXT NOT NULL,
  area       TEXT NOT NULL,
  rating     INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  text       TEXT NOT NULL,
  active     BOOLEAN NOT NULL DEFAULT true,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Before / After pairs (use gallery storage bucket, before_after/ folder)
CREATE TABLE IF NOT EXISTS public.before_after (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  before_path TEXT NOT NULL,
  before_url  TEXT NOT NULL,
  after_path  TEXT NOT NULL,
  after_url   TEXT NOT NULL,
  caption     TEXT NOT NULL DEFAULT '',
  sort_order  INTEGER NOT NULL DEFAULT 0,
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Business profile (singleton row)
CREATE TABLE IF NOT EXISTS public.business_profile (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  business_name   TEXT NOT NULL DEFAULT 'SK HomeCare',
  address         TEXT NOT NULL DEFAULT 'Aurangabad, Maharashtra',
  phone           TEXT NOT NULL DEFAULT '+91 87936 64463',
  email           TEXT NOT NULL DEFAULT 'skhomecareaurangabad@gmail.com',
  gst_number      TEXT,
  invoice_footer  TEXT DEFAULT 'Thank you for choosing SK HomeCare!',
  logo_url        TEXT,
  logo_path       TEXT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Invoice sequence
CREATE SEQUENCE IF NOT EXISTS public.invoice_seq START 1;

CREATE OR REPLACE FUNCTION public.next_invoice_no()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  RETURN 'SKH-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_seq')::TEXT, 4, '0');
END; $$;

CREATE TABLE IF NOT EXISTS public.invoices (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  invoice_no       TEXT UNIQUE NOT NULL DEFAULT public.next_invoice_no(),
  booking_id       UUID REFERENCES public.bookings(id) ON DELETE SET NULL,
  customer_name    TEXT NOT NULL,
  customer_phone   TEXT NOT NULL,
  customer_address TEXT NOT NULL,
  issue_date       DATE NOT NULL DEFAULT CURRENT_DATE,
  items            JSONB NOT NULL DEFAULT '[]',
  subtotal         NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount         NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  gst_percent      NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (gst_percent >= 0),
  gst_amount       NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (gst_amount >= 0),
  total            NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  payment_status   TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid','paid')),
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Per-invoice print design; the default keeps existing invoices on the reference-inspired style.
ALTER TABLE public.invoices ADD COLUMN IF NOT EXISTS template_id TEXT NOT NULL DEFAULT 'minimal-beige';

-- Follow-ups
CREATE TABLE IF NOT EXISTS public.follow_ups (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_phone   TEXT NOT NULL,
  customer_name    TEXT NOT NULL,
  last_service     TEXT NOT NULL,
  booking_id       UUID REFERENCES public.bookings(id) ON DELETE SET NULL,
  completed_date   DATE NOT NULL,
  due_date         DATE NOT NULL,
  status           TEXT NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active','contacted','snoozed','not_interested','do_not_contact')),
  last_contacted_at TIMESTAMPTZ,
  snooze_until     DATE,
  notes            TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════
-- UNIQUE SLOT INDEX (excludes cancelled)
-- ══════════════════════════════════════════════════════════════
CREATE UNIQUE INDEX IF NOT EXISTS bookings_unique_slot
  ON public.bookings (booking_date, booking_time)
  WHERE status <> 'cancelled';
  -- One active booking per time slot across the whole business.
  -- Multiple technicians: add a technician_id column and include it here.

-- ══════════════════════════════════════════════════════════════
-- ROW-LEVEL SECURITY
-- All tables: public can read (where appropriate), only
-- admin_users members can write.
-- ══════════════════════════════════════════════════════════════

-- Helper: is current user an admin?
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid());
$$;

DO $$ DECLARE t TEXT; BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'services','gallery','faqs','site_content','booking_settings',
    'bookings','reviews','before_after','business_profile','invoices','follow_ups'
  ]) LOOP
    EXECUTE 'ALTER TABLE public.' || t || ' ENABLE ROW LEVEL SECURITY';
  END LOOP;
END $$;

-- Drop existing policies safely
DO $$ DECLARE r RECORD; BEGIN
  FOR r IN SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public'
    AND tablename = ANY (ARRAY['services','gallery','faqs','site_content','booking_settings',
      'bookings','reviews','before_after','business_profile','invoices','follow_ups']) LOOP
    EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
  END LOOP;
END $$;

-- Public read policies
CREATE POLICY "pub_read_services"    ON public.services       FOR SELECT USING (active = true);
CREATE POLICY "pub_read_gallery"     ON public.gallery        FOR SELECT USING (true);
CREATE POLICY "pub_read_faqs"        ON public.faqs           FOR SELECT USING (active = true);
CREATE POLICY "pub_read_content"     ON public.site_content   FOR SELECT USING (true);
CREATE POLICY "pub_read_settings"    ON public.booking_settings FOR SELECT USING (true);
CREATE POLICY "pub_read_reviews"     ON public.reviews        FOR SELECT USING (active = true);
CREATE POLICY "pub_read_before_after" ON public.before_after  FOR SELECT USING (active = true);
CREATE POLICY "pub_read_profile"     ON public.business_profile FOR SELECT USING (true);
CREATE POLICY "pub_insert_bookings"  ON public.bookings       FOR INSERT WITH CHECK (true);

-- Admin-only write (all tables)
DO $$ DECLARE t TEXT; BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'services','gallery','faqs','site_content','booking_settings',
    'reviews','before_after','business_profile','invoices','follow_ups'
  ]) LOOP
    EXECUTE 'CREATE POLICY "admin_all_' || t || '" ON public.' || t ||
      ' FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())';
  END LOOP;
END $$;

-- Bookings: admin full access
CREATE POLICY "admin_read_bookings"   ON public.bookings FOR SELECT USING (public.is_admin());
CREATE POLICY "admin_update_bookings" ON public.bookings FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "admin_delete_bookings" ON public.bookings FOR DELETE USING (public.is_admin());

-- Table privileges required by PostgREST. RLS policies above still filter each row.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.services, public.gallery, public.faqs, public.site_content,
  public.booking_settings, public.reviews, public.before_after, public.business_profile
  TO anon, authenticated;
GRANT INSERT ON public.bookings TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.services, public.gallery, public.faqs,
  public.site_content, public.booking_settings, public.bookings, public.reviews,
  public.before_after, public.business_profile, public.invoices, public.follow_ups
  TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- STORAGE BUCKETS
-- ══════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('gallery', 'gallery', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('branding','branding',true, 2097152, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  DROP POLICY IF EXISTS "pub_read_gallery_obj"    ON storage.objects;
  DROP POLICY IF EXISTS "admin_write_gallery_obj" ON storage.objects;
  DROP POLICY IF EXISTS "admin_del_gallery_obj"   ON storage.objects;
  DROP POLICY IF EXISTS "pub_read_branding_obj"   ON storage.objects;
  DROP POLICY IF EXISTS "admin_write_branding_obj" ON storage.objects;
  DROP POLICY IF EXISTS "admin_del_branding_obj"  ON storage.objects;
END $$;

CREATE POLICY "pub_read_gallery_obj"     ON storage.objects FOR SELECT USING (bucket_id = 'gallery');
CREATE POLICY "admin_write_gallery_obj"  ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'gallery' AND public.is_admin());
CREATE POLICY "admin_del_gallery_obj"    ON storage.objects FOR DELETE USING (bucket_id = 'gallery' AND public.is_admin());
CREATE POLICY "pub_read_branding_obj"    ON storage.objects FOR SELECT USING (bucket_id = 'branding');
CREATE POLICY "admin_write_branding_obj" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'branding' AND public.is_admin());
CREATE POLICY "admin_del_branding_obj"   ON storage.objects FOR DELETE USING (bucket_id = 'branding' AND public.is_admin());

-- ══════════════════════════════════════════════════════════════
-- REALTIME (guard against duplicate table addition)
-- ══════════════════════════════════════════════════════════════
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'bookings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
  END IF;
END $$;

-- ══════════════════════════════════════════════════════════════
-- get_booked_slots (with search_path fix)
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_booked_slots(d date)
RETURNS TABLE(booking_time time)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT b.booking_time FROM public.bookings b
  WHERE b.booking_date = d AND b.status <> 'cancelled';
$$;
GRANT EXECUTE ON FUNCTION public.get_booked_slots(date) TO anon, authenticated;

-- ══════════════════════════════════════════════════════════════
-- TRIGGERS: auto-update updated_at
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DO $$ DECLARE t TEXT; BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'services','faqs','site_content','booking_settings',
    'invoices','follow_ups','business_profile'
  ]) LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS trg_' || t || '_updated ON public.' || t;
    EXECUTE 'CREATE TRIGGER trg_' || t || '_updated BEFORE UPDATE ON public.' || t ||
            ' FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()';
  END LOOP;
END $$;

-- ══════════════════════════════════════════════════════════════
-- DEFAULT DATA (all ON CONFLICT DO NOTHING — safe to re-run)
-- ══════════════════════════════════════════════════════════════
INSERT INTO public.services (icon,name,description,price,price_prefix,category,sort_order) VALUES
  ('❄️','AC Repair','Diagnosis first, then a quote. All faults — compressor, PCB, thermostat, cooling. Parts cost extra if needed.','₹1,000','From','ac',1),
  ('🧊','AC Normal Wash','Filter clean, coil flush, drain tray clean, blower wipe, gas pressure check, test run. Every 3 months recommended.','₹900','','ac',2),
  ('💧','AC Deep Wash','Outdoor unit opened, jet wash, chemical treatment, blower dismantle, drain pipe flush. Recommended annually.','₹1,500','','ac',3),
  ('⚙️','AC Installation','Professional installation by an experienced technician. Price is for labour only — customer supplies the AC unit.','₹2,200','','ac',4),
  ('🔩','AC Dismantling','Safe removal of indoor and outdoor units, pipe capping and gas recovery. Ready for transport.','₹1,500','','ac',5),
  ('🔥','AC Gas Refilling','R22, R32 or R410A refilling with pressure test. Final price depends on gas type and quantity.','₹4,500','From','ac',6),
  ('🫧','Washing Machine Repair','Not draining, spinning issues, leaking, error codes — all brands. Parts extra if needed.','₹1,200','From','other',7),
  ('🔧','Washing Machine Service','Full service — drum clean, filter, bearing and inlet valve check, test run.','₹1,000','','other',8),
  ('🧊','Refrigerator Repair','Not cooling, leaking, compressor or thermostat fault. Parts extra if needed.','₹1,200','From','other',9),
  ('💨','Air Cooler Repair','Pump issues, fan motor, bad smell, water leaking — all desert cooler repairs.','₹500','From','other',10),
  ('🌀','Fan Repair','Ceiling fan, table fan, exhaust fan — any fault. Same-day repair where possible.','₹500','From','other',11),
  ('🌡️','Geyser Repair','Not heating, tripping, leaking — element, thermostat and all geyser faults.','₹500','From','other',12),
  ('🌡️','Geyser Service','Full service — element check, thermostat test, flush and pressure check, test run.','₹1,200','','other',13)
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.faqs (question,answer,sort_order) VALUES
  ('How quickly can a technician reach me?','In most cases we can reach you the same day, often within a few hours.',1),
  ('Do you charge for the initial diagnosis?','For most services, the diagnosis is included. We quote before proceeding if extra cost is involved.',2),
  ('How does AC gas refilling pricing work?','We test first, tell you the cost, and only proceed with your approval.',3),
  ('Do you provide a warranty on repairs?','If the same fault returns within a reasonable period, call us and we will come back.',4),
  ('Can I book on a Sunday or public holiday?','Yes, we are available 7 days a week including most public holidays.',5),
  ('What AC brands do you service?','Samsung, LG, Daikin, Voltas, Blue Star, TCL, Godrej, Whirlpool, Hitachi, Carrier and others.',6),
  ('Does someone need to be home?','Yes, an adult should be present during the technician visit.',7)
ON CONFLICT (question) DO NOTHING;

INSERT INTO public.site_content (key,value,section,label) VALUES
  ('hero_heading','Your Home, Our Responsibility.','hero','Hero Heading'),
  ('hero_subtext','From AC installation and servicing to home appliance repairs — we tell you the price upfront, and we show up when we say we will.','hero','Hero Subtext'),
  ('book_btn_text','Book a Service','buttons','Main Book Button'),
  ('services_heading','Our services.','services','Services Heading'),
  ('gallery_heading','Our recent AC installations.','gallery','Gallery Heading'),
  ('gallery_subtext','Real installations. Real work. Service you can see.','gallery','Gallery Subtext'),
  ('annual_plan_price','₹2,500','annual_plan','Annual Care Plan Price'),
  ('annual_plan_desc','Two AC washes + one full inspection per year. Priority booking for plan holders.','annual_plan','Annual Care Plan Description')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.booking_settings (key,value) VALUES
  ('time_start','08:00'),
  ('time_end','20:00'),
  ('time_interval_hours','1'),
  ('max_days_ahead','30'),
  ('wa_number','+918793664463'),
  ('areas',E'Cidco\nN-1\nN-2\nN-3\nN-4\nN-5\nN-6\nN-7\nN-8\nGarkheda\nUlkanagari\nOsmanpura\nKranti Chowk\nSamarth Nagar\nJyoti Nagar\nShreya Nagar\nJawahar Colony\nSeven Hills\nAkashwani\nVedant Nagar\nCannaught Place\nTown Centre\nProzone Area\nJalna Road\nRailway Station Area\nCentral Bus Stand Area\nShahnoorwadi\nSatara Parisar\nBeed Bypass\nWaluj\nChikalthana\nHarsul\nOther Area'),
  ('followup_intervals','{"AC Normal Wash":90,"AC Deep Wash":365,"AC Gas Refilling":365,"AC Installation":365,"Geyser Service":365,"default":180}'),
  ('followup_template','Hello {name}, it has been {days} days since your {service} with SK HomeCare. Time for your next service? Reply to book or call +91 87936 64463.')
ON CONFLICT (key) DO NOTHING;

-- Seed default business profile (singleton)
INSERT INTO public.business_profile (business_name,address,phone,email,invoice_footer)
SELECT 'SK HomeCare Appliance Service','Aurangabad, Maharashtra','+91 87936 64463','skhomecareaurangabad@gmail.com','Thank you for choosing SK HomeCare!'
WHERE NOT EXISTS (SELECT 1 FROM public.business_profile);

-- ══════════════════════════════════════════════════════════════
-- ANTI-SPAM: server-side limits on public booking inserts
-- (admins bypass). Blocks floods, past/far-future dates and
-- one phone number hoarding slots.
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.guard_booking_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE today DATE := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  IF NEW.booking_date < today OR NEW.booking_date > today + 60 THEN
    RAISE EXCEPTION 'Invalid booking date';
  END IF;
  IF (SELECT count(*) FROM public.bookings
        WHERE phone = NEW.phone AND status IN ('pending','confirmed')
          AND booking_date >= today) >= 3 THEN
    RAISE EXCEPTION 'Too many active bookings for this number';
  END IF;
  IF (SELECT count(*) FROM public.bookings
        WHERE phone = NEW.phone AND created_at > now() - interval '10 minutes') >= 2 THEN
    RAISE EXCEPTION 'Please wait before booking again';
  END IF;
  IF (SELECT count(*) FROM public.bookings
        WHERE created_at > now() - interval '10 minutes') >= 30 THEN
    RAISE EXCEPTION 'Booking temporarily unavailable';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_booking_insert ON public.bookings;
CREATE TRIGGER trg_guard_booking_insert
  BEFORE INSERT ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.guard_booking_insert();

-- ══════════════════════════════════════════════════════════════
-- SECURITY FIXES (same as migration-001-security-fixes.sql)
-- ══════════════════════════════════════════════════════════════
-- 1. CRITICAL: admin_users had no Row Level Security. Anyone with the public
--    anon key could read it and, depending on grants, try to insert rows.
--    Lock it down: signed-in users may read ONLY their own row (the admin
--    login check needs this); nobody can write via the API. Add admins from
--    the SQL Editor (service role) only.
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_users FROM anon, authenticated;
GRANT SELECT ON public.admin_users TO authenticated;
DROP POLICY IF EXISTS "admin_read_self" ON public.admin_users;
CREATE POLICY "admin_read_self" ON public.admin_users
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- 2. Public booking insert could set status='completed' or write admin notes.
--    Public rows must always start as pending with no notes.
DROP POLICY IF EXISTS "pub_insert_bookings" ON public.bookings;
CREATE POLICY "pub_insert_bookings" ON public.bookings
  FOR INSERT TO anon, authenticated
  WITH CHECK (status = 'pending' AND notes IS NULL);

-- 3. Public could read every booking_settings row (follow-up templates etc).
--    Expose only the keys the customer website actually uses.
DROP POLICY IF EXISTS "pub_read_settings" ON public.booking_settings;
CREATE POLICY "pub_read_settings" ON public.booking_settings
  FOR SELECT USING (key IN ('time_start','time_end','time_interval_hours','max_days_ahead','wa_number','areas'));

-- 4. Extra input validation on public bookings (NOT VALID = existing rows are
--    not re-checked; every new insert/update is).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bookings_input_chk') THEN
    ALTER TABLE public.bookings ADD CONSTRAINT bookings_input_chk CHECK (
      length(btrim(name)) >= 2 AND length(service) BETWEEN 1 AND 100
      AND length(area) BETWEEN 1 AND 100 AND length(btrim(address)) >= 3
    ) NOT VALID;
  END IF;
END $$;

-- 5. Admin "follow-up" upsert uses ON CONFLICT (booking_id) but no unique
--    constraint existed, so it always failed. (If this errors, you already
--    have duplicate follow-ups for one booking: delete the duplicates first.)
CREATE UNIQUE INDEX IF NOT EXISTS follow_ups_booking_id_key ON public.follow_ups (booking_id);

-- 6. The invoice-number generator was callable by anonymous visitors through the
--    API (burning invoice numbers). Restrict to signed-in users.
REVOKE EXECUTE ON FUNCTION public.next_invoice_no() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.next_invoice_no() TO authenticated;

-- 7. Logo re-upload (upsert:true) needs an UPDATE policy on storage objects.
DROP POLICY IF EXISTS "admin_upd_branding_obj" ON storage.objects;
DROP POLICY IF EXISTS "admin_upd_gallery_obj"  ON storage.objects;
CREATE POLICY "admin_upd_branding_obj" ON storage.objects FOR UPDATE
  USING (bucket_id = 'branding' AND public.is_admin()) WITH CHECK (bucket_id = 'branding' AND public.is_admin());
CREATE POLICY "admin_upd_gallery_obj" ON storage.objects FOR UPDATE
  USING (bucket_id = 'gallery' AND public.is_admin()) WITH CHECK (bucket_id = 'gallery' AND public.is_admin());

-- ══════════════════════════════════════════════════════════════
-- INSERT ADMIN USER
-- Run AFTER creating the user in Dashboard → Authentication → Users
-- ══════════════════════════════════════════════════════════════
INSERT INTO public.admin_users (user_id)
SELECT id FROM auth.users WHERE email = 'shaikhayan7744@gmail.com'
ON CONFLICT DO NOTHING;
-- If this returns 0 rows, the user has not been created yet.
-- Create the user first, then re-run only this snippet.

-- ══════════════════════════════════════════════════════════════
-- VERIFY
-- ══════════════════════════════════════════════════════════════
-- SELECT name, price FROM services ORDER BY sort_order;
-- SELECT * FROM admin_users;
-- SELECT public.get_booked_slots(CURRENT_DATE);
