-- =============================================================================
-- MIGRACIÓN ONE-SHOT — Estado final ejecutado 2026-05-20
-- =============================================================================
-- Resultado: la tabla `public.ganancias_recolector` ahora tiene columna
-- `recolector_id` y los 2 acumulados legacy de Lourdes (IDs 23 y 24)
-- quedaron asociados a su recolector.
--
-- Sólo dejo el script aquí como REFERENCIA HISTÓRICA. NO RE-EJECUTAR.
-- Si tuvieras que repetir el procedimiento en otra base limpia:
-- =============================================================================

-- 1) Agregar columna (nullable, sin tocar lo existente):
-- ALTER TABLE public.ganancias_recolector
--   ADD COLUMN IF NOT EXISTS recolector_id uuid;
-- CREATE INDEX IF NOT EXISTS gr_recolector_idx
--   ON public.ganancias_recolector (recolector_id);

-- 2) Asociar huérfanos legacy al recolector que les corresponde:
-- UPDATE public.ganancias_recolector
--    SET recolector_id = '9c9cf2ae-8ea6-4944-8bb1-eeeeb6cd5436'  -- Lourdes
--  WHERE banquero_id = 'e4f51e2d-ceb5-4ea6-a806-0ee437d9956b'   -- Rubiel
--    AND recolector_id IS NULL
--    AND tipo <> 'cierre_diario';

-- Registros migrados:
--   id=23  comision=266684  "Ganancias Acumuladas del 28-07-25 al 22-04-26"
--   id=24  comision=833     "Día 22"

-- =============================================================================
-- ROLLBACK (si hubiera que deshacer)
-- =============================================================================
-- UPDATE public.ganancias_recolector
--    SET recolector_id = NULL
--  WHERE id IN (23, 24);
