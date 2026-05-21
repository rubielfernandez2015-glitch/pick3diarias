-- =============================================================================
-- BASELINE FUNCTIONS — snapshot 2026-05-21
-- =============================================================================
-- Todas las funciones (RPCs + helpers + triggers) de los schemas `banca` y
-- `public` (solo audit_log + historial_recolector). Se omiten funciones de
-- extensiones de Postgres (pg_trgm, uuid-ossp, etc.).
--
-- Cómo usar: si tenés que recrear la BD desde cero, correr este archivo
-- COMPLETO en SQL Editor de Supabase (todas las funciones se crean con
-- CREATE OR REPLACE, podés correrlo aunque ya existan).
--
-- IMPORTANTE: las tablas (`banca.*` y `public.*`) deben existir antes de
-- correr este script. Ver README.md para reconstrucción de tablas.
-- =============================================================================

-- =============================================================================
-- HELPERS (schema banca)
-- =============================================================================

CREATE OR REPLACE FUNCTION banca._banqueros_set_codigo()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
  BEGIN
    IF NEW.codigo IS NULL OR NEW.codigo = '' THEN
      NEW.codigo := banca._gen_codigo_banca();
    END IF;
    RETURN NEW;
  END $function$;

CREATE OR REPLACE FUNCTION banca._gen_codigo_banca()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
  DECLARE alf text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; c text; i int;
  BEGIN
    LOOP
      c := '';
      FOR i IN 1..5 LOOP c := c || substr(alf,(floor(random()*length(alf))+1)::int,1); END LOOP;
      EXIT WHEN NOT EXISTS (SELECT 1 FROM banca.banqueros WHERE upper(codigo)=upper(c));
    END LOOP;
    RETURN c;
  END $function$;

CREATE OR REPLACE FUNCTION banca._rec_por_token(p_token uuid)
 RETURNS banca.recolector_sesiones
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
      SELECT s.* FROM banca.recolector_sesiones s
       JOIN banca.recolectores r ON r.id = s.recolector_id
       WHERE s.token = p_token AND r.activo IS TRUE
       LIMIT 1;
  $function$;

-- =============================================================================
-- TRIGGER (en banca.banqueros) — asigna codigo de banca automaticamente
-- =============================================================================
-- Si no existe, recrear con:
--   CREATE TRIGGER trg_banqueros_codigo
--     BEFORE INSERT ON banca.banqueros
--     FOR EACH ROW EXECUTE FUNCTION banca._banqueros_set_codigo();

-- =============================================================================
-- LOGIN RECOLECTOR (2 overloads)
-- =============================================================================

CREATE OR REPLACE FUNCTION banca.login_recolector(p_username text, p_password_hash text)
 RETURNS TABLE(token uuid, id uuid, nombre text, username text, comision numeric, banquero_id uuid, activo boolean, sesion_noche boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE r banca.recolectores%ROWTYPE; t uuid;
    BEGIN
      SELECT rec.* INTO r FROM banca.recolectores AS rec
       WHERE rec.username = lower(p_username) AND rec.password_hash = p_password_hash;
      IF NOT FOUND THEN RETURN; END IF;
      IF r.activo IS NOT TRUE THEN
        RETURN QUERY SELECT NULL::uuid, r.id, r.nombre, r.username, r.comision,
                            r.banquero_id, r.activo, r.sesion_noche;
        RETURN;
      END IF;
      INSERT INTO banca.recolector_sesiones(recolector_id, banquero_id)
           VALUES (r.id, r.banquero_id) RETURNING recolector_sesiones.token INTO t;
      RETURN QUERY SELECT t, r.id, r.nombre, r.username, r.comision,
                          r.banquero_id, r.activo, r.sesion_noche;
    END $function$;

CREATE OR REPLACE FUNCTION banca.login_recolector(p_codigo text, p_username text, p_password_hash text)
 RETURNS TABLE(token uuid, id uuid, nombre text, username text, comision numeric, banquero_id uuid, activo boolean, sesion_noche boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE v_bid uuid; r banca.recolectores%ROWTYPE; t uuid;
    BEGIN
      SELECT b.id INTO v_bid FROM banca.banqueros b WHERE upper(b.codigo) = upper(p_codigo);
      IF v_bid IS NULL THEN RETURN; END IF;
      SELECT rec.* INTO r FROM banca.recolectores AS rec
       WHERE rec.banquero_id = v_bid
         AND rec.username = lower(p_username)
         AND rec.password_hash = p_password_hash;
      IF NOT FOUND THEN RETURN; END IF;
      IF r.activo IS NOT TRUE THEN
        RETURN QUERY SELECT NULL::uuid, r.id, r.nombre, r.username, r.comision,
                            r.banquero_id, r.activo, r.sesion_noche;
        RETURN;
      END IF;
      INSERT INTO banca.recolector_sesiones(recolector_id, banquero_id)
           VALUES (r.id, r.banquero_id) RETURNING recolector_sesiones.token INTO t;
      RETURN QUERY SELECT t, r.id, r.nombre, r.username, r.comision,
                          r.banquero_id, r.activo, r.sesion_noche;
    END $function$;

-- =============================================================================
-- RECOLECTOR: lecturas/escrituras via token (sin Supabase-Auth)
-- =============================================================================

CREATE OR REPLACE FUNCTION banca.recolector_jugadas_fecha(p_token uuid, p_fecha date)
 RETURNS SETOF public.jugadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE s banca.recolector_sesiones;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      RETURN QUERY SELECT * FROM public.jugadas
        WHERE recolector_id = s.recolector_id
          AND (fecha = p_fecha::text OR dia_cierre = p_fecha::text)
        ORDER BY id ASC;
    END $function$;

CREATE OR REPLACE FUNCTION banca.recolector_jugadas_dia(p_token uuid, p_fecha date)
 RETURNS SETOF public.jugadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE s banca.recolector_sesiones;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      RETURN QUERY SELECT * FROM public.jugadas
        WHERE dia_cierre = p_fecha::text AND recolector_id = s.recolector_id
        ORDER BY id ASC;
    END $function$;

CREATE OR REPLACE FUNCTION banca.recolector_jugadas_pendientes(p_token uuid, p_fecha date)
 RETURNS SETOF public.jugadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE s banca.recolector_sesiones;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      RETURN QUERY SELECT * FROM public.jugadas
        WHERE fecha = p_fecha::text AND dia_cierre IS NULL
          AND banquero_id = s.banquero_id AND recolector_id = s.recolector_id
        ORDER BY id ASC;
    END $function$;

CREATE OR REPLACE FUNCTION banca.recolector_insertar_jugadas(p_token uuid, p_cliente text, p_fecha date, p_sesion text, p_jugadas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
  DECLARE s banca.recolector_sesiones; n integer;
  BEGIN
    s := banca._rec_por_token(p_token);
    IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
    INSERT INTO public.jugadas(fecha,cliente,decena,pick,centena,numero,monto,hora,
                               dia_cierre,sesion,recolector_id,banquero_id)
    SELECT p_fecha, p_cliente,
           j->>'dec', j->>'pick', '0', (j->>'dec')||(j->>'pick'),
           (j->>'monto')::numeric, j->>'hora', NULL, p_sesion,
           s.recolector_id, s.banquero_id
      FROM jsonb_array_elements(p_jugadas) j;
    GET DIAGNOSTICS n = ROW_COUNT;
    INSERT INTO public.clientes(nombre, ultimo, banquero_id)
         VALUES (p_cliente, p_fecha::text, s.banquero_id)
    ON CONFLICT (nombre, banquero_id) DO UPDATE SET ultimo = excluded.ultimo;
    RETURN n;
  END $function$;

-- Etapa 2 (commit b21316a + Etapa 2 hardening): lecturas via token
CREATE OR REPLACE FUNCTION banca.recolector_resultados(p_token uuid, p_fechas text[] DEFAULT NULL::text[], p_sesiones text[] DEFAULT NULL::text[])
 RETURNS SETOF public.resultados
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE
      s banca.recolector_sesiones;
      v_banq_id uuid;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      SELECT banquero_id INTO v_banq_id
        FROM banca.recolectores WHERE id = s.recolector_id;
      RETURN QUERY
        SELECT *
          FROM public.resultados r
         WHERE r.banquero_id = v_banq_id
           AND (p_fechas   IS NULL OR r.fecha  = ANY(p_fechas))
           AND (p_sesiones IS NULL OR r.sesion = ANY(p_sesiones));
    END
  $function$;

CREATE OR REPLACE FUNCTION banca.recolector_clientes(p_token uuid, p_q text, p_limit integer DEFAULT 6)
 RETURNS TABLE(nombre text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE
      s banca.recolector_sesiones;
      v_banq_id uuid;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      SELECT banquero_id INTO v_banq_id
        FROM banca.recolectores WHERE id = s.recolector_id;
      RETURN QUERY
        SELECT c.nombre
          FROM public.clientes c
         WHERE c.banquero_id = v_banq_id
           AND c.nombre ILIKE (p_q || '%')
           AND c.nombre NOT LIKE E'\\_\\_%'
         ORDER BY c.nombre
         LIMIT GREATEST(1, LEAST(p_limit, 20));
    END
  $function$;

CREATE OR REPLACE FUNCTION banca.acumulados_recolector(p_token uuid)
 RETURNS SETOF public.ganancias_recolector
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE
      s banca.recolector_sesiones;
      v_banq_id uuid;
    BEGIN
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN RAISE EXCEPTION 'TOKEN_INVALIDO'; END IF;
      SELECT banquero_id INTO v_banq_id
        FROM banca.recolectores WHERE id = s.recolector_id;
      RETURN QUERY
        SELECT *
          FROM public.ganancias_recolector
         WHERE recolector_id = s.recolector_id
           AND banquero_id   = v_banq_id
           AND tipo <> 'cierre_diario'
         ORDER BY created_at ASC;
    END
  $function$;

CREATE OR REPLACE FUNCTION banca.cambiar_password_recolector(p_token uuid, p_nueva_hash text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca', 'public'
AS $function$
    DECLARE
      s banca.recolector_sesiones;
    BEGIN
      IF p_nueva_hash IS NULL OR length(p_nueva_hash) < 8 THEN
        RAISE EXCEPTION 'HASH_INVALIDO';
      END IF;
      s := banca._rec_por_token(p_token);
      IF s.token IS NULL THEN
        RAISE EXCEPTION 'TOKEN_INVALIDO';
      END IF;
      UPDATE banca.recolectores
         SET password_hash = p_nueva_hash
       WHERE id = s.recolector_id;
    END
  $function$;

-- =============================================================================
-- CIERRE DE SESION (Punto 4 F2) — calculo server-side autoritativo
-- =============================================================================

CREATE OR REPLACE FUNCTION banca.cerrar_sesion(p_fecha text, p_sesion text, p_numero text, p_incluir_legacy boolean DEFAULT true)
 RETURNS TABLE(n_jugadas integer, pick text, rec numeric, prem numeric, com numeric, ganb numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'banca'
AS $function$
  DECLARE
    v_bid uuid; v_num text; v_pick text;
    v_rec numeric; v_prem numeric; v_com numeric; v_ganb numeric;
    v_ids bigint[]; v_n int;
    v_base numeric; v_acum numeric; v_gan numeric; v_aju numeric; v_fondo numeric;
    v_hoy text;
  BEGIN
    v_bid := auth.uid();
    IF v_bid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_num  := lpad((NULLIF(regexp_replace(p_numero,'[^0-9]','','g'),''))::int::text, 3, '0');
    v_pick := substr(v_num, 2, 2);

    SELECT array_agg(j.id) INTO v_ids
    FROM public.jugadas j
    WHERE j.dia_cierre IS NULL AND j.fecha::text = p_fecha
      AND j.sesion = p_sesion AND j.banquero_id = v_bid;

    IF (v_ids IS NULL OR array_length(v_ids,1) IS NULL) AND p_incluir_legacy THEN
      SELECT array_agg(j.id) INTO v_ids
      FROM public.jugadas j
      WHERE j.dia_cierre IS NULL AND j.fecha::text = p_fecha AND j.banquero_id = v_bid;
    END IF;

    v_n := COALESCE(array_length(v_ids,1), 0);

    SELECT round(COALESCE(sum(j.monto::numeric),0),2)
      INTO v_rec
    FROM public.jugadas j WHERE j.id = ANY(v_ids);

    SELECT round(COALESCE(sum(j.monto::numeric * 80),0),2)
      INTO v_prem
    FROM public.jugadas j WHERE j.id = ANY(v_ids) AND j.pick = v_pick;

    IF v_rec > 0 THEN
      SELECT round(COALESCE(sum( j.monto::numeric * (COALESCE(NULLIF(rc.comision,0),15)/100.0) ),0),2)
        INTO v_com
      FROM public.jugadas j
      LEFT JOIN banca.recolectores rc ON rc.id = j.recolector_id
      WHERE j.id = ANY(v_ids) AND j.recolector_id IS NOT NULL;
    ELSE
      v_com := 0;
    END IF;
    v_com  := COALESCE(v_com,0);
    v_ganb := round(v_rec - v_com - v_prem, 2);

    IF v_n > 0 THEN
      UPDATE public.jugadas SET dia_cierre = p_fecha WHERE id = ANY(v_ids);
    END IF;

    INSERT INTO public.resultados (fecha,sesion,numero,pick,ts,total_rec,total_premios,comision_rec,ganancia_banquero,banquero_id)
    VALUES (p_fecha,p_sesion,v_num,v_pick,now(),v_rec,v_prem,v_com,v_ganb,v_bid)
    ON CONFLICT (fecha,sesion,banquero_id)
    DO UPDATE SET numero=excluded.numero, pick=excluded.pick, ts=excluded.ts,
                  total_rec=excluded.total_rec, total_premios=excluded.total_premios,
                  comision_rec=excluded.comision_rec, ganancia_banquero=excluded.ganancia_banquero;

    v_hoy := (now() AT TIME ZONE 'America/New_York')::date::text;
    INSERT INTO public.ganancias_recolector (fecha,total_rec,comision,nota,tipo,banquero_id)
    VALUES (p_fecha, v_rec, v_com,
            'Comisión cierre '||p_sesion||' · Pick '||v_pick||' · '||v_num
              || CASE WHEN p_fecha <> v_hoy THEN ' · Día '||p_fecha ELSE '' END,
            'cierre_diario', v_bid);

    v_base := COALESCE((SELECT NULLIF(ultimo,'')::numeric FROM public.clientes WHERE nombre='__FONDO_BASE__' AND banquero_id=v_bid LIMIT 1),0);
    v_acum := COALESCE((SELECT NULLIF(ultimo,'')::numeric FROM public.clientes WHERE nombre='__FONDO_ACUM__' AND banquero_id=v_bid LIMIT 1),0);
    v_gan  := round(COALESCE((SELECT sum(ganancia_banquero) FROM public.resultados WHERE banquero_id=v_bid),0),2);
    v_aju  := round(COALESCE((SELECT sum(monto) FROM public.fondo_movimientos WHERE banquero_id=v_bid),0),2);
    v_fondo := round(v_base + v_acum + v_gan + v_aju, 2);
    INSERT INTO public.clientes (nombre,ultimo,banquero_id)
    VALUES ('__FONDO__', v_fondo::text, v_bid)
    ON CONFLICT (nombre,banquero_id) DO UPDATE SET ultimo=excluded.ultimo;

    RETURN QUERY SELECT v_n, v_pick, v_rec, v_prem, v_com, v_ganb;
  END $function$;

CREATE OR REPLACE FUNCTION banca.cerrar_sesion_preview(p_fecha text, p_sesion text, p_banquero_id uuid)
 RETURNS TABLE(n_jugadas integer, pick text, rec_calc numeric, prem_calc numeric, com_calc numeric, ganb_calc numeric, rec_guardado numeric, prem_guardado numeric, com_guardado numeric, ganb_guardado numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'banca'
AS $function$
  DECLARE v_pick text; v_rec numeric; v_prem numeric; v_com numeric; v_ganb numeric; r_res record;
  BEGIN
    SELECT res.pick, res.numero, res.total_rec, res.total_premios, res.comision_rec, res.ganancia_banquero
      INTO r_res
    FROM public.resultados res
    WHERE res.fecha::text = p_fecha AND res.sesion = p_sesion AND res.banquero_id = p_banquero_id
    LIMIT 1;
    IF NOT FOUND THEN RETURN; END IF;

    v_pick := COALESCE(r_res.pick, substr(lpad(r_res.numero::text,3,'0'),2,2));

    SELECT round(COALESCE(sum(j.monto::numeric),0),2)
      INTO v_rec
    FROM public.jugadas j
    WHERE j.dia_cierre::text = p_fecha AND j.sesion = p_sesion AND j.banquero_id = p_banquero_id;

    SELECT round(COALESCE(sum(j.monto::numeric * 80),0),2)
      INTO v_prem
    FROM public.jugadas j
    WHERE j.dia_cierre::text = p_fecha AND j.sesion = p_sesion AND j.banquero_id = p_banquero_id
      AND j.pick = v_pick;

    IF v_rec > 0 THEN
      SELECT round(COALESCE(sum( j.monto::numeric * (COALESCE(NULLIF(rc.comision,0),15) / 100.0) ),0),2)
        INTO v_com
      FROM public.jugadas j
      LEFT JOIN banca.recolectores rc ON rc.id = j.recolector_id
      WHERE j.dia_cierre::text = p_fecha AND j.sesion = p_sesion AND j.banquero_id = p_banquero_id
        AND j.recolector_id IS NOT NULL;
    ELSE
      v_com := 0;
    END IF;
    v_com := COALESCE(v_com,0);
    v_ganb := round(v_rec - v_com - v_prem, 2);

    RETURN QUERY
    SELECT
      (SELECT count(*)::int FROM public.jugadas j2 WHERE j2.dia_cierre::text=p_fecha AND j2.sesion=p_sesion AND j2.banquero_id=p_banquero_id),
      v_pick, v_rec, v_prem, v_com, v_ganb,
      round(r_res.total_rec::numeric,2), round(r_res.total_premios::numeric,2),
      round(r_res.comision_rec::numeric,2), round(r_res.ganancia_banquero::numeric,2);
  END $function$;

-- =============================================================================
-- ADMIN (banquero autenticado): CRUD de recolectores + movimientos
-- =============================================================================

CREATE OR REPLACE FUNCTION banca.crear_recolector(p_username text, p_password_hash text, p_nombre text, p_comision numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  INSERT INTO banca.recolectores (banquero_id, username, password_hash, nombre, comision)
  VALUES (auth.uid(), p_username, p_password_hash, p_nombre, p_comision)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION banca.editar_recolector(p_id uuid, p_nombre text, p_comision numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  UPDATE banca.recolectores
  SET nombre=p_nombre, comision=p_comision
  WHERE id=p_id AND banquero_id=auth.uid();
END;
$function$;

CREATE OR REPLACE FUNCTION banca.eliminar_recolector(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  DELETE FROM banca.recolectores WHERE id=p_id AND banquero_id=auth.uid();
END;
$function$;

CREATE OR REPLACE FUNCTION banca.toggle_recolector(p_id uuid, p_activo boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  UPDATE banca.recolectores SET activo=p_activo WHERE id=p_id AND banquero_id=auth.uid();
END;
$function$;

CREATE OR REPLACE FUNCTION banca.mis_recolectores()
 RETURNS SETOF banca.recolectores
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  RETURN QUERY
    SELECT * FROM banca.recolectores
    WHERE banquero_id = auth.uid()
    ORDER BY created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION banca.movimientos_recolector(p_recolector_id uuid)
 RETURNS SETOF banca.recolector_movimientos
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  RETURN QUERY SELECT * FROM banca.recolector_movimientos
    WHERE recolector_id=p_recolector_id AND banquero_id=auth.uid()
    ORDER BY created_at DESC;
END;$function$;

CREATE OR REPLACE FUNCTION banca.registrar_movimiento_recolector(p_recolector_id uuid, p_tipo text, p_monto numeric, p_nota text, p_fecha text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
  INSERT INTO banca.recolector_movimientos(recolector_id,banquero_id,tipo,monto,nota,fecha)
  VALUES(p_recolector_id,auth.uid(),p_tipo,p_monto,p_nota,p_fecha);
END;$function$;

-- =============================================================================
-- LEGACY (puede no estar en uso — mantener por compatibilidad)
-- =============================================================================

CREATE OR REPLACE FUNCTION banca.mis_jugadas(p_fecha text DEFAULT NULL::text)
 RETURNS SETOF banca.jugadas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'banca'
AS $function$
BEGIN
  RETURN QUERY
    SELECT * FROM banca.jugadas
    WHERE recolector_id = (
      SELECT id FROM banca.recolectores WHERE id::text = current_setting('app.recolector_id', true)
    )
    AND (p_fecha IS NULL OR fecha = p_fecha)
    ORDER BY id DESC;
END;
$function$;

-- =============================================================================
-- SCHEMA public: auditoria + historial
-- =============================================================================

CREATE OR REPLACE FUNCTION public.audit_log(p_accion text, p_detalle jsonb DEFAULT '{}'::jsonb, p_recolector_id uuid DEFAULT NULL::uuid, p_token uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'banca'
AS $function$
  DECLARE
    v_banquero_id   uuid;
    v_recolector_id uuid;
    v_session       banca.recolector_sesiones;
  BEGIN
    IF p_token IS NOT NULL THEN
      v_session := banca._rec_por_token(p_token);
      IF v_session.token IS NULL THEN
        RAISE EXCEPTION 'TOKEN_INVALIDO';
      END IF;
      v_recolector_id := v_session.recolector_id;
      SELECT banquero_id INTO v_banquero_id
        FROM banca.recolectores WHERE id = v_recolector_id;
    ELSE
      v_banquero_id := auth.uid();
      IF v_banquero_id IS NULL THEN
        RAISE EXCEPTION 'SIN_SESION';
      END IF;
      IF p_recolector_id IS NOT NULL THEN
        IF NOT EXISTS (
          SELECT 1 FROM banca.recolectores
           WHERE id = p_recolector_id AND banquero_id = v_banquero_id
        ) THEN
          RAISE EXCEPTION 'RECOLECTOR_INVALIDO';
        END IF;
        v_recolector_id := p_recolector_id;
      END IF;
    END IF;

    INSERT INTO public.auditoria(banquero_id, recolector_id, accion, detalle)
    VALUES (v_banquero_id, v_recolector_id, p_accion, p_detalle);
  END
  $function$;

CREATE OR REPLACE FUNCTION public.historial_recolector(p_recolector_id uuid)
 RETURNS TABLE(dia_cierre text, total_jugadas bigint, total_rec numeric, total_prem numeric, pick_ganador text, numero_ganador text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    j.dia_cierre,
    COUNT(*)::BIGINT as total_jugadas,
    SUM(j.monto) as total_rec,
    COALESCE(SUM(CASE WHEN j.pick = r.pick THEN j.monto * 80 ELSE 0 END), 0) as total_prem,
    r.pick as pick_ganador,
    r.numero as numero_ganador
  FROM public.jugadas j
  LEFT JOIN public.resultados r ON r.fecha = j.dia_cierre
  WHERE j.recolector_id = p_recolector_id
    AND j.dia_cierre IS NOT NULL
  GROUP BY j.dia_cierre, r.pick, r.numero
  ORDER BY j.dia_cierre DESC;
END;
$function$;

-- =============================================================================
-- GRANTS (las RPCs token-aware necesitan ser ejecutables por anon)
-- =============================================================================

GRANT EXECUTE ON FUNCTION banca.login_recolector(text, text)             TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.login_recolector(text, text, text)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_jugadas_fecha(uuid, date)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_jugadas_dia(uuid, date)       TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_jugadas_pendientes(uuid, date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_insertar_jugadas(uuid, text, date, text, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_resultados(uuid, text[], text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.recolector_clientes(uuid, text, integer)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.acumulados_recolector(uuid)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION banca.cambiar_password_recolector(uuid, text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_log(text, jsonb, uuid, uuid)       TO anon, authenticated;

-- Funciones admin-only (requieren auth.uid()): solo a authenticated
GRANT EXECUTE ON FUNCTION banca.cerrar_sesion(text, text, text, boolean)  TO authenticated;
GRANT EXECUTE ON FUNCTION banca.crear_recolector(text, text, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION banca.editar_recolector(uuid, text, numeric)    TO authenticated;
GRANT EXECUTE ON FUNCTION banca.eliminar_recolector(uuid)                  TO authenticated;
GRANT EXECUTE ON FUNCTION banca.toggle_recolector(uuid, boolean)           TO authenticated;
GRANT EXECUTE ON FUNCTION banca.mis_recolectores()                         TO authenticated;
GRANT EXECUTE ON FUNCTION banca.movimientos_recolector(uuid)               TO authenticated;
GRANT EXECUTE ON FUNCTION banca.registrar_movimiento_recolector(uuid, text, numeric, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.historial_recolector(uuid)                TO authenticated;
