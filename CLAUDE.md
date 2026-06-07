# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A PWA for managing "La Bolita" / Florida Pick 3 lottery banking. The frontend is **plain static files with no build step** (vanilla HTML/JS/CSS, no `package.json`, no bundler). The backend is **Supabase** (Postgres + Auth + Edge Functions + Realtime). It runs in **production today** with real banqueros — treat the database as live.

The codebase (comments, identifiers, UI strings) is in **Spanish**. Match that when writing code.

## Commands

- **Run locally:** `node _localserver.mjs` → open http://localhost:8080 (zero-dependency static server with aggressive no-cache so reloads always get the latest).
- **Deploy frontend to production:** `git push origin main`. The app is served by **GitHub Pages** from `main`, so a push *is* the production deploy. (User preference: push to production when a task is done.)
- **Deploy an Edge Function:** Supabase Dashboard → Edge Functions → paste the function's `index.ts` → Deploy. **Not** done via git push. Names must be exact: `smooth-api`, `recognize-jugada`. `smooth-api` must be deployed **public** (Verify JWT OFF).
- **Run a SQL migration:** paste the file into the Supabase SQL Editor and run; files in `migrations/` are run in numeric order. Then commit the file.

There is **no test/lint/build tooling**. Manual regression testing is tracked in `CHECKLIST_REGRESION_ETAPA4.md`.

## Architecture

### Frontend
- **`index.html`** is the entire app (~330 KB): all UI and logic in one file, terse minified-style vanilla JS (short names, packed lines — match that density). Config (Supabase URL + public anon key) is at the top of the `<script>` (~line 1225).
- **`sw.js`** — service worker. Bump `CACHE_NAME` (`bolita-vN`) to force clients to update. It deliberately does **not** intercept `supabase.co` requests (always online).
- **`resumen.html`** — standalone photos→WhatsApp-summary tool, no login/DB. Gated by a client-side `TOOL_KEY` that must match the `RESUMEN_TOOL_KEY` Edge Function secret (a lightweight gate, not real auth).
- **`lab/ocr-test.html`** — scratch page for OCR experimentation.

### Two roles, two auth paths
- **admin / banquero:** Supabase Auth (email + password). `banqueroId` = the auth user id.
- **recolector (collector):** logs in via the `login_recolector` RPC (banca code + username + SHA-256 password hash) and receives a **token** (`recToken`, kept in `localStorage`). Recolectores have **no direct table access** — every read/write goes through `SECURITY DEFINER` RPCs named `recolector_*` that validate the token server-side. A `TOKEN_INVALIDO` error means the session expired → auto-logout (`_tokenMurio`).

### Supabase data model
- App data lives in the **`banca`** schema, accessed as `sb.schema('banca')...`; `public` holds cross-cutting RPCs like `audit_log`. `migrations/00_baseline_*.sql` are the versioned snapshot of functions, RLS policies, grants, and realtime subscriptions (table DDL is **not** versioned — tables predate the snapshot). See `migrations/README.md`.
- **Multi-tenant:** the system is multi-banquero. Every query must be scoped by banca; cross-banca data leaks are a recurring hazard that's been audited before. The offline IndexedDB queue is also scoped by banca.

### Domain rules to respect
- **Timezone:** the app's "today" (`etHoy()`) is **US Eastern**, not Havana — many date helpers hardcode `America/New_York`. Do not change this.
- **Draws:** Florida Pick 3 has two sessions per day — `dia` (midday) and `noche` (evening).
- **Anti-cheating ("anti-trampa"):** registration cutoff is a per-banquero ON/OFF setting (`04_corte_banquero.sql`); separate from anti past-posting (`01_anti_postresultado.sql`) which blocks edits after a result is applied. Audit triggers (`02_auditoria_triggers.sql`) record actions with server-derived identity. Be careful editing close/cutoff logic.
- **Server-side close:** session close is computed server-side via the `cerrar_sesion` RPC (`cerrar_sesion_preview` is a read-only variant). Don't reintroduce client-side close math.
- **Offline:** jugadas registered offline are queued in IndexedDB and synced on reconnect (service worker `sync` → client `SYNC_REQUEST`). State is also re-synced on visibility change via `detectarSesionActiva`.

### Edge Functions (`supabase/functions/`)
- **`smooth-api`** — fetches the latest Florida Pick 3 result via Jina Reader and caches it in `public.resultado_cache` (instant repeat reads, anti-hammer, resilient fallback to cache). The `build` field in its JSON response identifies the deployed version.
- **`recognize-jugada`** — OCR of handwritten bet photos via Gemini; validates the caller (recolector token or banquero JWT) before spending Gemini quota.

## Secrets / config conventions
- Edge Function secrets are read with `Deno.env.get(...)` and set in the Supabase Dashboard: `JINA_KEY`, `GEMINI_API_KEY`, `GEMINI_MODEL` (optional), `RESUMEN_TOOL_KEY`. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically — do not set them.
- The `sb_publishable_...` anon key in `index.html`/`resumen.html` is **public by design** (RLS protects the data); it is not a leak. Never hardcode any other key in source.

## Conventions
- Escape all user-supplied data with `esc()` before inserting into `innerHTML` (stored-XSS defense).
- Match the existing terse style in `index.html`; the rest of the repo uses ordinary readable JS/SQL.
