-- =============================================================================
-- 01 — ANTI PAST-POSTING (jugadas despues del resultado)  ·  2026-05-30
-- =============================================================================
-- PROBLEMA QUE CIERRA:
--   El bloqueo "ya cerro, no registres" vivia SOLO en el cliente (isSesionCerrada
--   / regla de corte). Un atacante con token de recolector valido, o el banquero
--   mismo, podian saltarse la UI y llamar las RPC/inserts directos para meter una
--   jugada GANADORA despues de conocerse el numero de Florida (past-posting).
--
-- DEFENSA (server-side, autoritativa, cubre TODOS los caminos de insercion):
--   (a) Trigger BEFORE INSERT en public.jugadas. Cuando la sesion YA tiene
--       resultado (fecha+sesion+banca):
--         * Si la jugada es GANADORA (su pick coincide con el numero ya salido)
--           -> RECHAZA. Unico caso con incentivo de fraude (past-posting).
--         * Si es PERDEDORA -> la ACEPTA (no roba nada) pero deja constancia en
--           public.auditoria como 'db:jugadas:tardia' para revision del banquero.
--       Cubre tanto el insert del recolector (RPC recolector_insertar_jugadas)
--       como el insert directo del banquero (sb.from('jugadas').insert).
--   (b) Guarda dentro de banca.cerrar_sesion: rechaza re-cerrar una sesion que
--       ya tiene resultado (version server de la guarda anti-doble-cierre que
--       hoy solo existe en el cliente, linea ~2930 de index.html).
--
-- POR QUE NO ROMPE NADA LEGITIMO:
--   - No toca el campo `hora`: la jugada se guarda con su hora de recoleccion.
--   - Jugadas de hoy antes del resultado / de manana: no hay resultado -> pasan.
--   - Jugadas offline PERDEDORAS sincronizadas tarde: pasan (y quedan logueadas).
--   - Correccion de numero: se hace con "Revertir" (revertirCierre), que BORRA la
--     fila de resultados y reabre con UPDATE (no INSERT). Tras revertir no hay
--     resultado -> se puede re-cerrar y, si hiciera falta, re-insertar.
--   - El UNICO rechazo es la jugada GANADORA llegada despues del resultado. Una
--     ganadora legitima sincronizada tardisimo (rara) se resuelve a mano:
--     Revertir -> agregarla -> re-cerrar.
-- NOTA: `hora`/`created_at` son inservibles como prueba de seguridad (el cliente
-- los manda y un atacante los falsea; created_at de un sync tardio tambien cae
-- despues del resultado). Por eso el criterio robusto es "ganadora o no".
--
-- Idempotente: se puede correr varias veces (CREATE OR REPLACE / DROP IF EXISTS).
-- Correr COMPLETO en el SQL Editor de Supabase.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (a) Trigger anti past-posting en public.jugadas
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER es OBLIGATORIO: anon tiene REVOCADO el SELECT sobre
-- public.resultados (ver 00_baseline_grants.sql). Si el trigger corriera como
-- el rol llamador (anon), el EXISTS daria "permission denied". Como definer
-- (owner postgres) puede leer resultados; el filtro banquero_id lo mantiene
-- correctamente aislado por banca.
CREATE OR REPLACE FUNCTION public.jugadas_bloquea_post_resultado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'banca'
AS $function$
  DECLARE v_pick text; v_found boolean;
  BEGIN
    IF NEW.dia_cierre IS NULL AND NEW.sesion IS NOT NULL THEN
      SELECT r.pick INTO v_pick
        FROM public.resultados r
       WHERE r.banquero_id = NEW.banquero_id
         AND r.fecha::text = NEW.fecha::text
         AND r.sesion      = NEW.sesion
       LIMIT 1;
      v_found := FOUND;

      IF v_found THEN
        -- La sesion ya tiene resultado conocido.
        IF NEW.pick = v_pick THEN
          -- Jugada GANADORA llegada despues del cierre -> past-posting. Bloquear.
          RAISE EXCEPTION
            'SESION_CERRADA_GANADORA: la sesion % del % ya tiene resultado (pick %); no se acepta una jugada ganadora despues del cierre (anti past-posting). Para incluirla legitimamente, reverti el cierre primero.',
            NEW.sesion, NEW.fecha, v_pick
            USING ERRCODE = 'check_violation';
        ELSE
          -- Jugada PERDEDORA tardia -> se permite, pero queda constancia.
          INSERT INTO public.auditoria(banquero_id, recolector_id, accion, detalle)
          VALUES (
            NEW.banquero_id, NEW.recolector_id, 'db:jugadas:tardia',
            jsonb_build_object(
              'fecha', NEW.fecha, 'sesion', NEW.sesion, 'pick', NEW.pick,
              'monto', NEW.monto, 'cliente', NEW.cliente, 'hora', NEW.hora,
              'pick_ganador', v_pick, 'actor_uid', auth.uid(), 'ts', now()
            )
          );
        END IF;
      END IF;
    END IF;
    RETURN NEW;
  END
$function$;

DROP TRIGGER IF EXISTS trg_jugadas_post_resultado ON public.jugadas;
CREATE TRIGGER trg_jugadas_post_resultado
  BEFORE INSERT ON public.jugadas
  FOR EACH ROW
  EXECUTE FUNCTION public.jugadas_bloquea_post_resultado();


-- -----------------------------------------------------------------------------
-- (b) Guarda anti re-cierre dentro de banca.cerrar_sesion
-- -----------------------------------------------------------------------------
-- Identica a la version del baseline + el bloque "GUARDA ANTI RE-CIERRE".
-- Si ya existe resultado para (fecha, sesion, banca) -> aborta. El cliente ya
-- lo evita (linea ~2930), pero asi queda blindado tambien ante llamadas directas.
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

    -- GUARDA ANTI RE-CIERRE (server-side, 2026-05-30):
    -- no permitir cerrar una sesion que ya tiene resultado. Para cambiar el
    -- numero hay que Revertir (que borra el resultado) y volver a cerrar.
    IF EXISTS (
      SELECT 1 FROM public.resultados r
       WHERE r.banquero_id = v_bid
         AND r.fecha::text  = p_fecha
         AND r.sesion       = p_sesion
    ) THEN
      RAISE EXCEPTION
        'SESION_YA_CERRADA: ya existe resultado para % %. Reverti el cierre antes de re-cerrar.',
        p_fecha, p_sesion
        USING ERRCODE = 'unique_violation';
    END IF;

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


-- =============================================================================
-- VERIFICACION (correr despues; opcional)
-- =============================================================================
-- 1) El trigger existe y esta habilitado:
/*
SELECT tgname, tgenabled
  FROM pg_trigger
 WHERE tgrelid = 'public.jugadas'::regclass AND NOT tgisinternal;
*/
-- 2) Prueba en vivo (banca de prueba): cerra una sesion con un numero, luego:
--    - Inserta una jugada GANADORA (pick = el numero salido) para esa
--      fecha+sesion -> debe FALLAR con 'SESION_CERRADA_GANADORA'.
--    - Inserta una jugada PERDEDORA -> debe PASAR, y aparece en auditoria como
--      'db:jugadas:tardia'.
--    - Reverti el cierre -> ambos inserts vuelven a funcionar sin restriccion.
