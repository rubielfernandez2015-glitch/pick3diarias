-- =============================================================================
-- 02 — AUDITORIA A PRUEBA DE MANIPULACION (triggers en BD)  ·  2026-05-30
-- =============================================================================
-- PROBLEMA QUE CIERRA:
--   La auditoria existente (RPC public.audit_log) es VOLUNTARIA: solo se escribe
--   cuando el cliente decide llamarla. Un atacante que llame las RPC/SQL directo
--   (saltandose la UI) NO deja rastro. Ademas el propio banquero podia BORRAR sus
--   filas de auditoria (policy FOR ALL) -> no era a prueba de manipulacion.
--
-- DEFENSA:
--   (a) Trigger generico public.audit_row_change() que registra AUTOMATICAMENTE
--       en public.auditoria cualquier cambio en las tablas sensibles, venga de
--       donde venga (app, token robado, llamada directa). Captura quien
--       (auth.uid()), que operacion, y la fila completa.
--   (b) Auditoria pasa a SOLO-INSERT: se revoca UPDATE/DELETE a anon y
--       authenticated, asi ni el banquero puede limpiar el rastro.
--
-- ALCANCE (alto valor / bajo ruido). Se auditan los vectores de fraude reales:
--   - public.clientes          INSERT/UPDATE/DELETE  (incluye __FONDO_*  = el fondo)
--   - public.fondo_movimientos INSERT/UPDATE/DELETE  (ajustes manuales del fondo)
--   - public.jugadas           DELETE                (borrar jugadas para defraudar)
--   - public.resultados        DELETE                (revertir / cambiar el numero)
--   - banca.recolectores       INSERT/UPDATE/DELETE  (altas/bajas/claves de cuentas)
--   Se OMITEN a proposito: jugadas INSERT (flujo normal, y el past-posting ya lo
--   bloquea 01), jugadas UPDATE y resultados INSERT/UPDATE (ruido de cada cierre,
--   que ademas la app ya audita con accion CIERRE_DIA).
--
-- Idempotente. Correr COMPLETO en el SQL Editor de Supabase DESPUES de 01.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (a) Funcion de trigger generica
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER: corre como owner -> puede insertar en public.auditoria
-- (bypassa RLS/grants) sin importar el rol llamador. auth.uid() sigue
-- devolviendo el usuario real (lee el claim del JWT, que DEFINER no altera),
-- por eso atribuye correctamente al banquero autenticado.
CREATE OR REPLACE FUNCTION public.audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'banca'
AS $function$
  DECLARE
    v_banq uuid;
    v_row  jsonb;
    v_old  jsonb;
  BEGIN
    IF TG_OP = 'DELETE' THEN
      v_row := to_jsonb(OLD);
    ELSE
      v_row := to_jsonb(NEW);
    END IF;

    -- Nunca guardar el hash de clave en la auditoria.
    v_row := v_row - 'password_hash';
    IF TG_OP = 'UPDATE' THEN
      v_old := to_jsonb(OLD) - 'password_hash';
    END IF;

    -- Banca duena de la fila: el actor autenticado, o el banquero_id de la fila.
    v_banq := COALESCE(auth.uid(), NULLIF(v_row->>'banquero_id','')::uuid);

    INSERT INTO public.auditoria(banquero_id, recolector_id, accion, detalle)
    VALUES (
      v_banq,
      NULLIF(v_row->>'recolector_id','')::uuid,
      'db:'||TG_TABLE_NAME||':'||lower(TG_OP),
      jsonb_strip_nulls(jsonb_build_object(
        'op',        TG_OP,
        'tabla',     TG_TABLE_NAME,
        'fila',      v_row,
        'anterior',  v_old,
        'actor_uid', auth.uid(),
        'ts',        now()
      ))
    );
    RETURN NULL; -- AFTER trigger: valor de retorno ignorado
  END
$function$;

-- -----------------------------------------------------------------------------
-- (b) Enganchar triggers en las tablas sensibles
-- -----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_audit_clientes ON public.clientes;
CREATE TRIGGER trg_audit_clientes
  AFTER INSERT OR UPDATE OR DELETE ON public.clientes
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_fondo_mov ON public.fondo_movimientos;
CREATE TRIGGER trg_audit_fondo_mov
  AFTER INSERT OR UPDATE OR DELETE ON public.fondo_movimientos
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_jugadas_del ON public.jugadas;
CREATE TRIGGER trg_audit_jugadas_del
  AFTER DELETE ON public.jugadas
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_resultados_del ON public.resultados;
CREATE TRIGGER trg_audit_resultados_del
  AFTER DELETE ON public.resultados
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_audit_recolectores ON banca.recolectores;
CREATE TRIGGER trg_audit_recolectores
  AFTER INSERT OR UPDATE OR DELETE ON banca.recolectores
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

-- -----------------------------------------------------------------------------
-- (c) Auditoria = SOLO-INSERT (nadie puede borrar/editar el rastro)
-- -----------------------------------------------------------------------------
-- El INSERT legitimo entra por SECURITY DEFINER (este trigger + public.audit_log),
-- que bypassan grants. El banquero conserva SELECT para consultar su auditoria,
-- pero pierde UPDATE/DELETE. (La policy auditoria_banquero sigue filtrando por
-- banca en las lecturas.)
REVOKE UPDATE, DELETE ON public.auditoria FROM anon;
REVOKE UPDATE, DELETE ON public.auditoria FROM authenticated;


-- =============================================================================
-- VERIFICACION (opcional, correr despues)
-- =============================================================================
-- 1) Triggers creados:
/*
SELECT n.nspname AS schema, c.relname AS tabla, t.tgname
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE t.tgname LIKE 'trg_audit_%' AND NOT t.tgisinternal
 ORDER BY 1,2,3;
*/
-- 2) Prueba: en una banca de prueba, edita el __FONDO_BASE__ o borra una jugada,
--    luego:  SELECT accion, detalle FROM public.auditoria ORDER BY id DESC LIMIT 5;
--    Debe aparecer la fila 'db:clientes:update' / 'db:jugadas:delete'.
-- 3) Confirma que ya NO podes borrar auditoria como banquero:
--    DELETE FROM public.auditoria WHERE id = <alguno>;  -> permission denied.
