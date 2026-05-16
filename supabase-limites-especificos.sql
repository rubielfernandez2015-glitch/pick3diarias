-- ═══════════════════════════════════════════════════════════
-- LA BOLITA PLUS · SQL Migración · Límites Específicos
-- Ejecutar en Supabase → SQL Editor
-- Solo necesitas 1 línea en la tabla que ya existe
-- ═══════════════════════════════════════════════════════════

-- Agregar columna JSON a la tabla que YA EXISTE
-- (Si ya tienes la tabla limites_numeros, esto es todo)
ALTER TABLE public.limites_numeros
  ADD COLUMN IF NOT EXISTS limites_esp JSONB DEFAULT '{}'::jsonb;

-- ✅ Listo. No hace falta crear ninguna tabla nueva.
-- Los límites específicos se guardan como JSON junto
-- a la configuración global de límites del banquero.

-- ─────────────────────────────────────────────────────────
-- VERIFICAR que quedó bien (ejecutar después):
SELECT banquero_id, monto_limite, tipo_limite, limites_esp
FROM public.limites_numeros
LIMIT 5;
