-- =============================================================================
-- BASELINE RLS POLICIES — snapshot 2026-05-21
-- =============================================================================
-- Policies de Row-Level Security en schemas `public` y `banca`. La proteccion
-- real del multi-banca es la combinacion de:
--   1. RLS policies (este archivo)
--   2. GRANTs explicitos (ver 00_baseline_grants.sql)
--   3. RPCs SECURITY DEFINER (ver 00_baseline_functions.sql) que validan token
--
-- Para recrear: asegurarse de que las tablas existan y la RLS este ENABLED:
--   ALTER TABLE public.jugadas ENABLE ROW LEVEL SECURITY;
--   (idem para cada tabla)
-- Despues correr estos CREATE POLICY.
-- =============================================================================

-- =============================================================================
-- ⚠️  POLICIES "acceso total" — DEPRECATED, RECOMENDADO ELIMINAR
-- =============================================================================
-- Estas policies son LEGACY (creadas cuando la app era single-banca). Dejan
-- pasar TODO con `qual=true`. El REVOKE de grants en Etapa 2 las hace inertes
-- (no se evalua RLS si no hay grant SELECT), pero si alguien re-grant a anon,
-- toda la fuga se abre.
--
-- Para limpiarlas (correr una sola vez):
--   DROP POLICY IF EXISTS "acceso total" ON public.clientes;
--   DROP POLICY IF EXISTS "acceso total" ON public.limites_numeros;
--   DROP POLICY IF EXISTS "acceso total" ON public.resultados;
-- =============================================================================

-- Estas existian al snapshot — NO recrear si se piensan eliminar:
-- CREATE POLICY "acceso total" ON public.clientes        FOR ALL TO public USING (true) WITH CHECK (true);
-- CREATE POLICY "acceso total" ON public.limites_numeros FOR ALL TO public USING (true) WITH CHECK (true);
-- CREATE POLICY "acceso total" ON public.resultados      FOR ALL TO public USING (true) WITH CHECK (true);


-- =============================================================================
-- SCHEMA banca
-- =============================================================================

-- banca.banqueros — el banquero solo ve/edita SU propio registro.
CREATE POLICY banquero_select ON banca.banqueros
  FOR SELECT TO public USING (auth.uid() = id);

CREATE POLICY banquero_insert ON banca.banqueros
  FOR INSERT TO public WITH CHECK (auth.uid() = id);

CREATE POLICY banquero_update ON banca.banqueros
  FOR UPDATE TO public USING (auth.uid() = id);

-- banca.recolectores — el banquero gestiona los recolectores de SU banca.
-- El SELECT tambien permite anon (para que el cliente del recolector pueda
-- leer su propia fila al validar via app.recolector_id; el resto va via RPC).
CREATE POLICY recolector_select ON banca.recolectores
  FOR SELECT TO anon, authenticated
  USING (
    (auth.uid() = banquero_id) OR
    (current_setting('role'::text) = 'anon'::text)
  );

CREATE POLICY recolector_insert ON banca.recolectores
  FOR INSERT TO public WITH CHECK (auth.uid() = banquero_id);

CREATE POLICY recolector_update ON banca.recolectores
  FOR UPDATE TO public USING (auth.uid() = banquero_id);

CREATE POLICY recolector_delete ON banca.recolectores
  FOR DELETE TO public USING (auth.uid() = banquero_id);


-- =============================================================================
-- SCHEMA public — aislamiento por banquero_id (RLS multi-banca)
-- =============================================================================

-- public.jugadas — tabla critica de dinero. RLS permite:
--   (a) banquero autenticado (auth.uid() = banquero_id) → admin
--   (b) recolector que setea app.recolector_id en su sesion → vista limitada
CREATE POLICY jugadas_banquero ON public.jugadas
  FOR ALL TO public
  USING (
    (banquero_id = auth.uid()) OR
    (banquero_id IN (
      SELECT recolectores.banquero_id
        FROM banca.recolectores
       WHERE (recolectores.id)::text = current_setting('app.recolector_id'::text, true)
    ))
  );

-- public.resultados — solo admin de la banca (acceso recolector via RPC).
CREATE POLICY resultados_banquero ON public.resultados
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.clientes — incluye filas especiales __FONDO_BASE__ / __FONDO_ACUM__ / __FONDO__.
CREATE POLICY clientes_banquero ON public.clientes
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.fondo_movimientos — ajustes manuales del fondo, solo admin.
CREATE POLICY fondo_banquero ON public.fondo_movimientos
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.ganancias_recolector — comisiones (cierres + acumulados manuales).
CREATE POLICY ganancias_banquero ON public.ganancias_recolector
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.limites_numeros — limites de exposicion por numero.
CREATE POLICY limites_banquero ON public.limites_numeros
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.auditoria — log de acciones (insert via RPC public.audit_log).
CREATE POLICY auditoria_banquero ON public.auditoria
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.banquero_ajustes — preferencias del banquero (modo resultado, etc).
CREATE POLICY banquero_sus_ajustes ON public.banquero_ajustes
  FOR ALL TO public USING (banquero_id = auth.uid());

-- public.comision_historial — historial de cambios de comision por recolector.
CREATE POLICY banquero_ve_sus_comisiones ON public.comision_historial
  FOR ALL TO public USING (banquero_id = auth.uid());
