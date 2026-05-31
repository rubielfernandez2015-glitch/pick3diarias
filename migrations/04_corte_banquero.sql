-- =============================================================================
-- 04 — RESTRICCIÓN DE CIERRE configurable por banquero  ·  2026-05-31
-- =============================================================================
-- Permite al banquero activar/desactivar el corte por HORA (para él y su equipo).
-- OJO: esto NO afecta el anti past-posting (trigger en jugadas): aunque el corte
-- por hora esté OFF, una jugada GANADORA después del resultado SIEMPRE se rechaza.
-- Correr COMPLETO en el SQL Editor. Idempotente.
-- =============================================================================

-- Columna del ajuste (default true = comportamiento actual; nadie cambia salvo que lo apague).
ALTER TABLE public.banquero_ajustes
  ADD COLUMN IF NOT EXISTS corte_activo boolean NOT NULL DEFAULT true;

-- El recolector (anon + token) no puede leer banquero_ajustes (RLS). Este RPC
-- le expone SOLO si el corte está activo para su banca.
CREATE OR REPLACE FUNCTION banca.recolector_corte_activo(p_token uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
  DECLARE s banca.recolector_sesiones; v boolean;
  BEGIN
    s := banca._rec_por_token(p_token);
    IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
    SELECT corte_activo INTO v FROM public.banquero_ajustes WHERE banquero_id = s.banquero_id;
    RETURN COALESCE(v, true);  -- por defecto: corte activo
  END
$function$;

GRANT EXECUTE ON FUNCTION banca.recolector_corte_activo(uuid) TO anon, authenticated;
