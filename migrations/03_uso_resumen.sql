-- =============================================================================
-- 03 — METRICA DE USO de la herramienta de resumen (resumen.html)  ·  2026-05-31
-- =============================================================================
-- Registra CUANTO usa cada banca la herramienta de conteo por fotos. NO toca
-- jugadas ni contabilidad: es solo una tabla de metricas aparte.
-- La Edge Function recognize-jugada llama a log_uso_resumen(codigo) cuando la
-- herramienta lee una foto (el codigo viene en la URL ?b=ABC12).
-- Correr COMPLETO en el SQL Editor. Idempotente.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.uso_resumen (
  codigo      text        NOT NULL,
  dia         date        NOT NULL,
  fotos       integer     NOT NULL DEFAULT 0,
  actualizado timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (codigo, dia)
);

-- Solo el service_role (la funcion) y el dueno (SQL Editor) la tocan. Nadie por API.
ALTER TABLE public.uso_resumen ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.uso_resumen FROM anon;
REVOKE ALL ON public.uso_resumen FROM authenticated;

-- Incrementa el contador del dia para esa banca (hora del Este).
CREATE OR REPLACE FUNCTION public.log_uso_resumen(p_codigo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_codigo IS NULL OR btrim(p_codigo) = '' THEN RETURN; END IF;
  INSERT INTO public.uso_resumen (codigo, dia, fotos, actualizado)
  VALUES (upper(btrim(p_codigo)), (now() AT TIME ZONE 'America/New_York')::date, 1, now())
  ON CONFLICT (codigo, dia)
  DO UPDATE SET fotos = uso_resumen.fotos + 1, actualizado = now();
END
$function$;


-- =============================================================================
-- CONSULTA: quien usa la herramienta y cuanto (correr cuando quieras)
-- =============================================================================
/*
SELECT
  u.codigo,
  au.email,
  sum(u.fotos)            AS fotos_total,
  count(DISTINCT u.dia)   AS dias_usados,
  max(u.dia)              AS ultimo_uso
FROM public.uso_resumen u
LEFT JOIN banca.banqueros b ON upper(b.codigo) = u.codigo
LEFT JOIN auth.users au      ON au.id = b.id
GROUP BY u.codigo, au.email
ORDER BY fotos_total DESC;
*/
