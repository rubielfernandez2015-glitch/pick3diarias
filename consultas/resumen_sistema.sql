-- =============================================================================
-- RESUMEN DEL SISTEMA — vigilancia de uso (banqueros / recolectores / jugadas)
-- =============================================================================
-- Correr en el SQL Editor de Supabase. Sirve para saber cuanta gente usa la app
-- y detectar bancas que NO reconoces (= la app se compartio con alguien mas).
-- Tip: el editor muestra el resultado de la ULTIMA consulta. Corre cada bloque
-- por separado (selecciona el bloque y "Run"), o comenta los otros.
-- =============================================================================

-- ── BLOQUE 1: Totales globales (una sola fila) ──
SELECT
  (SELECT count(*) FROM banca.banqueros)                                  AS total_banqueros,
  (SELECT count(*) FROM banca.recolectores)                              AS total_recolectores,
  (SELECT count(*) FROM banca.recolectores WHERE activo IS TRUE)         AS recolectores_activos,
  (SELECT count(*) FROM public.jugadas)                                   AS total_jugadas,
  (SELECT round(coalesce(sum(monto::numeric),0),2) FROM public.jugadas)   AS monto_total_global;


-- ── BLOQUE 2: Desglose por banca (lo mas util para detectar desconocidos) ──
-- Lista CADA banquero: su codigo, correo, cuando se registro, cuantos
-- recolectores/jugadas tiene y su ultima actividad.
SELECT
  b.codigo                                                                 AS banca,
  u.email                                                                  AS correo,
  b.created_at::date                                                       AS registrado,
  (SELECT count(*) FROM banca.recolectores r WHERE r.banquero_id = b.id)   AS recolectores,
  (SELECT count(*) FROM public.jugadas j     WHERE j.banquero_id = b.id)   AS jugadas,
  (SELECT round(coalesce(sum(j.monto::numeric),0),2)
     FROM public.jugadas j WHERE j.banquero_id = b.id)                     AS monto_total,
  (SELECT max(j.created_at)::date
     FROM public.jugadas j WHERE j.banquero_id = b.id)                     AS ultima_actividad
FROM banca.banqueros b
LEFT JOIN auth.users u ON u.id = b.id
ORDER BY b.created_at;


-- ── BLOQUE 3: Recolectores por banca (opcional, mas detalle) ──
SELECT
  b.codigo            AS banca,
  r.nombre            AS recolector,
  r.username,
  r.activo,
  r.created_at::date  AS creado
FROM banca.recolectores r
JOIN banca.banqueros b ON b.id = r.banquero_id
ORDER BY b.codigo, r.created_at;
