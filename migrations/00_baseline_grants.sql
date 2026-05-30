-- =============================================================================
-- BASELINE GRANTS / REVOKES — snapshot 2026-05-21
-- =============================================================================
-- Estado de privilegios SQL por rol (anon, authenticated) en tablas criticas.
--
-- Estrategia de seguridad multi-capa:
--   1. RLS policies (00_baseline_policies.sql) → filtra filas por banquero_id.
--   2. GRANTs/REVOKEs (este archivo)          → quita el privilegio mismo.
--   3. RPCs SECURITY DEFINER (functions.sql)  → unica via legitima para anon.
--
-- Por defecto Supabase otorga TODOS los privilegios (SELECT/INSERT/UPDATE/
-- DELETE/REFERENCES/TRIGGER/TRUNCATE) a anon y authenticated en las tablas
-- de public/banca al crearlas. Despues se aplican REVOKEs especificos para
-- cerrar fugas: ese es el rol de este archivo.
-- =============================================================================

-- =============================================================================
-- REVOKEs APLICADOS (Etapa 2 + Auditoria a prueba de manipulacion)
-- =============================================================================
-- Si recreas la BD desde cero, despues de crear las tablas correr esto.

-- Etapa 2 (2026-05-21): el recolector ya no necesita SELECT directo;
-- lee resultados/clientes via banca.recolector_resultados y
-- banca.recolector_clientes (RPC SECURITY DEFINER token-aware).
REVOKE SELECT ON public.resultados FROM anon;
REVOKE SELECT ON public.clientes   FROM anon;

-- Auditoria a prueba de manipulacion (2026-05-21): el cliente ya no
-- inserta directo; usa public.audit_log (RPC SECURITY DEFINER que
-- valida banquero_id desde auth.uid() o token recolector).
REVOKE INSERT ON public.auditoria FROM anon;

-- Auditoria SOLO-INSERT (2026-05-30, ver migrations/02_auditoria_triggers.sql):
-- nadie (ni el banquero) puede borrar/editar el rastro. El INSERT legitimo
-- entra por SECURITY DEFINER (triggers public.audit_row_change + audit_log).
REVOKE UPDATE, DELETE ON public.auditoria FROM anon;
REVOKE UPDATE, DELETE ON public.auditoria FROM authenticated;


-- =============================================================================
-- ESTADO ACTUAL CONFIRMADO (al snapshot)
-- =============================================================================
-- Tablas que anon NO tiene grant alguno (ni siquiera SELECT):
--   public.jugadas → solo authenticated. Tabla critica de dinero, blindada.
--
-- Tablas con SELECT bloqueado a anon (REVOKE aplicado):
--   public.resultados → solo authenticated puede SELECT directo.
--   public.clientes   → solo authenticated puede SELECT directo.
--
-- Tablas con INSERT bloqueado a anon (REVOKE aplicado):
--   public.auditoria → solo authenticated puede INSERT directo.
--                      anon escribe via public.audit_log (SECURITY DEFINER).


-- =============================================================================
-- ⚠️  HARDENING ADICIONAL RECOMENDADO (NO aplicado al snapshot)
-- =============================================================================
-- Las siguientes tablas tienen anon con todos los privilegios. RLS las protege
-- (qual = banquero_id = auth.uid() → false para anon), pero es defensa unica.
-- Recomendado: revocar grants de anon ya que el recolector NO accede
-- directamente a estas tablas en la app actual.
--
-- ANTES de aplicar: confirmar via grep del index.html que ninguna llamada
-- del cliente recolector toca estas tablas directamente. Si alguna lo hace,
-- migrar primero a RPC token-aware (patron Etapa 2).
--
-- REVOKE ALL ON public.banquero_ajustes    FROM anon;
-- REVOKE ALL ON public.fondo_movimientos   FROM anon;
-- REVOKE ALL ON public.ganancias_recolector FROM anon;
-- REVOKE ALL ON public.limites_numeros     FROM anon;
-- REVOKE ALL ON public.comision_historial  FROM anon;
--
-- En banca.* hay grants amplios a anon que tampoco necesita (la app del
-- recolector va por RPCs banca.* o por banca.recolectores select limitado):
-- REVOKE ALL ON banca.banqueros               FROM anon;
-- REVOKE ALL ON banca.recolector_movimientos  FROM anon;
-- REVOKE ALL ON banca.recolector_sesiones     FROM anon;
-- REVOKE ALL ON banca.jugadas                 FROM anon;
-- (banca.recolectores SI necesita SELECT a anon — esta documentado en la policy)


-- =============================================================================
-- VERIFICACION POST-CAMBIOS
-- =============================================================================
-- Listar privilegios actuales de anon en tablas criticas:
/*
SELECT table_schema, table_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE grantee = 'anon'
   AND table_schema IN ('public','banca')
   AND table_name IN ('jugadas','resultados','clientes','auditoria',
                      'fondo_movimientos','ganancias_recolector',
                      'limites_numeros','banquero_ajustes','comision_historial',
                      'banqueros','recolectores','recolector_sesiones',
                      'recolector_movimientos')
 ORDER BY table_schema, table_name, privilege_type;
*/
