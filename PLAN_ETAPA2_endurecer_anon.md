# 🔒 Plan Etapa 2 — Cerrar fuga de `resultados` y `clientes` (recolector anon)

**Estado:** diferido a post-release v1.0 (limitación documentada). Plan completo para retomar cuando se decida ejecutar.
**No bloquea v1.0** — la app ya está aislada por banca en `jugadas` (la tabla crítica de dinero). Lo que queda es lectura cross-banca de **nombres de clientes** y **números/picks** de otras bancas, vía la `publishable key` + endpoint exacto.

---

## Auditoría actualizada 2026-05-20 (líneas vigentes)

Lecturas directas a `resultados`/`clientes` ejecutables por **recolector anon**:

| # | Línea | Función | Tabla | Propósito |
|---|-------|---------|-------|-----------|
| 1 | 1595 | `doAC` (autocomplete) | `clientes` | sugerencias de nombre al registrar jugada |
| 2 | 1640 | `isSesionCerrada` (hot-path) | `resultados` | chequeo de cierre antes de registrar/cambiar UI |
| 3 | 2852 | `loadResR` rama día+noche cerradas | `resultados` | trae cierre noche cuando ambas cerradas |
| 4 | 2866 | `loadResR` sesión actual | `resultados` | número/pick para mostrar al recolector |
| 5 | 2882 | `loadResR` fallback huérfano | `resultados` | resultado día antes de 14:30 si huérfano |
| 6 | 2994 | `cargarInfoModoResultado` | `resultados` | info del cierre actual |
| 7 | 3149 | `togHistRec` | `resultados` | número/pick de un día expandido |
| 8 | 3271 | `loadGR` | `resultados` | resultado del día para ganancias rec |

> Líneas pueden desplazarse en futuros commits. Volver a correr el grep antes de tocar:
> `sb\.from\(.(resultados|clientes).\)` filtrado por rol recolector.

Admin lee igual estas tablas (líneas 3091, 3234, 3370, 3801, 3870, 3873, 3980, 4131, 4169, 4522…) pero ya está autenticado (`auth.uid()`) y RLS por banca funciona para él vía policy `resultados_banquero`/`clientes_banquero` (verificar que existan en panel Supabase antes de tocar nada).

---

## RPCs propuestas (server-side, SECURITY DEFINER, token-aware)

```sql
-- ============================================================
-- 1) banca.recolector_resultados
-- Cubre puntos #2, #3, #4, #5, #6, #7, #8 de la tabla.
-- Devuelve todas las columnas de resultados que el cliente necesita.
-- ============================================================
CREATE OR REPLACE FUNCTION banca.recolector_resultados(
  p_token   text,
  p_fechas  text[]    DEFAULT NULL,   -- NULL = sin filtro de fecha
  p_sesiones text[]   DEFAULT NULL    -- NULL = ambas sesiones
)
RETURNS TABLE(
  fecha             text,
  sesion            text,
  numero            text,
  pick              text,
  total_rec         numeric,
  total_premios     numeric,
  comision_rec      numeric,
  ganancia_banquero numeric,
  created_at        timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_banquero uuid;
BEGIN
  -- Resuelve banquero desde token; si no existe/vencido → excepción.
  v_banquero := banca._rec_por_token(p_token);
  IF v_banquero IS NULL THEN
    RAISE EXCEPTION 'TOKEN_INVALIDO' USING ERRCODE='P0001';
  END IF;
  RETURN QUERY
    SELECT r.fecha, r.sesion, r.numero, r.pick, r.total_rec, r.total_premios,
           r.comision_rec, r.ganancia_banquero, r.created_at
      FROM public.resultados r
     WHERE r.banquero_id = v_banquero
       AND (p_fechas   IS NULL OR r.fecha  = ANY(p_fechas))
       AND (p_sesiones IS NULL OR r.sesion = ANY(p_sesiones));
END $$;

REVOKE ALL ON FUNCTION banca.recolector_resultados(text,text[],text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION banca.recolector_resultados(text,text[],text[]) TO anon, authenticated;

-- ============================================================
-- 2) banca.recolector_clientes — autocomplete de nombres
-- Cubre punto #1.
-- ============================================================
CREATE OR REPLACE FUNCTION banca.recolector_clientes(
  p_token text,
  p_q     text,
  p_limit int DEFAULT 6
)
RETURNS TABLE(nombre text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_banquero uuid;
BEGIN
  v_banquero := banca._rec_por_token(p_token);
  IF v_banquero IS NULL THEN
    RAISE EXCEPTION 'TOKEN_INVALIDO' USING ERRCODE='P0001';
  END IF;
  RETURN QUERY
    SELECT c.nombre
      FROM public.clientes c
     WHERE c.banquero_id = v_banquero
       AND c.nombre ILIKE (p_q || '%')
       AND c.nombre NOT LIKE '\_\_%'  -- excluye __FONDO__, __FONDO_BASE__, etc.
     ORDER BY c.nombre
     LIMIT GREATEST(1, LEAST(p_limit, 20));
END $$;

REVOKE ALL ON FUNCTION banca.recolector_clientes(text,text,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION banca.recolector_clientes(text,text,int) TO anon, authenticated;
```

---

## Cambios en `index.html` (8 sitios)

Mismo patrón en cada uno: si `rol==='recolector'`, usar RPC; sino, dejar la lectura directa (admin tiene RLS por banca con su JWT).

### 1. `doAC` (autocomplete clientes) — línea 1595
```js
if(rol==='recolector'){
  const {data,error}=await sb.schema('banca').rpc('recolector_clientes',{p_token:recToken,p_q:q,p_limit:6});
  if(_tokenMurio(error)){l.classList.remove('on');return;}
  if(!data||!data.length){l.classList.remove('on');return;}
  // …resto igual…
}else{
  const {data}=await sb.from('clientes').select('nombre').ilike('nombre',q+'%').not('nombre','like','\\_\\_%').eq('banquero_id',bIdCA).limit(6);
  if(!data||!data.length){l.classList.remove('on');return;}
}
```

### 2. `isSesionCerrada` — línea 1640
```js
if(rol==='recolector'){
  const {data,error}=await sb.schema('banca').rpc('recolector_resultados',{p_token:recToken,p_fechas:[etHoy()],p_sesiones:[sesion]});
  if(_tokenMurio(error))return false;
  return !!(data&&data.length);
}else{
  const{data}=await sb.from('resultados').select('numero').eq('fecha',etHoy()).eq('sesion',sesion).eq('banquero_id',banqueroId||'').maybeSingle();
  return !!data;
}
```

### 3-6. `loadResR` (líneas 2852, 2866, 2882, 2994) y `cargarInfoModoResultado` (2994)
Reemplazar los 4 maybeSingle por **una sola llamada RPC** que traiga las 2-3 filas relevantes del día, y luego filtrar en JS:
```js
if(rol==='recolector'){
  const {data,error}=await sb.schema('banca').rpc('recolector_resultados',{p_token:recToken,p_fechas:[fecha],p_sesiones:null});
  if(_tokenMurio(error))return;
  const resTodos=data||[];
  const res=resTodos.find(r=>r.sesion===sesion);
  const resN=resTodos.find(r=>r.sesion==='noche');
  const resD=resTodos.find(r=>r.sesion==='dia');
  // …usar res/resN/resD igual que ahora…
}else{ /* lecturas directas igual que hoy */ }
```

### 7. `togHistRec` (línea 3149)
```js
if(rol==='recolector'){
  const {data,error}=await sb.schema('banca').rpc('recolector_resultados',{p_token:recToken,p_fechas:[fecha]});
  if(!_tokenMurio(error))(data||[]).forEach(r=>{resPorSes[r.sesion||'dia']={numero:r.numero,pick:r.pick};});
}else{ /* …select directo igual… */ }
```

### 8. `loadGR` (línea 3271)
Similar: si recolector, traer `recolector_resultados([hoy],[sesionActual])`.

---

## Orden de ejecución (cuando se decida hacerlo)

1. **Desplegar las 2 RPCs en Supabase** (Editor SQL).
2. **Probar las RPCs sueltas** con curl + token de Lourdes:
   ```
   curl -X POST 'https://<proj>.supabase.co/rest/v1/rpc/recolector_resultados' \
     -H 'apikey: <publishable>' -H 'Content-Type: application/json' \
     -d '{"p_token":"<token>","p_fechas":["2026-05-20"]}'
   ```
3. **Reescribir los 8 sitios** en `index.html` (rama recolector → RPC; rama admin igual).
4. **Validar en localhost** con login recolector real: autocomplete, registro, resultado, historial, ganancias.
5. **Cuando todo OK**: `REVOKE SELECT ON public.resultados FROM anon;` + `REVOKE SELECT ON public.clientes FROM anon;` (la jugada de gracia anti-fuga).
6. **Probar de nuevo** que recolector sigue 100% operativo tras el revoke.
7. **Publicar** index.html (commit + push).

**ROLLBACK:** `GRANT SELECT ON public.resultados TO anon;` `GRANT SELECT ON public.clientes TO anon;` + revertir commit index.html.

---

## Estimación

- RPCs SQL: ~30 min (escribir + desplegar + curl tests).
- Reescritura cliente: ~60 min (8 sitios, patrón repetitivo).
- Pruebas localhost: ~30 min.
- Revoke + re-prueba: ~15 min.
- **Total: ~2.5 hs** dedicadas. Razonable para una tarde tranquila post-release.

---

## Por qué se difiere (registro de decisión)

El plan rector del 25/05 lo etiqueta "ENDURECIMIENTO, no bloqueante". Razones:
1. **`jugadas` ya está blindada** (Parte C cerrada): el dinero no es leíble cross-banca.
2. La fuga restante es **nombres** (`clientes`) y **números/picks** (`resultados`). Sin dinero, sin contraseñas.
3. Requiere `publishable key` (pública en el HTML) + conocer exactamente los endpoints + saber que existe ese banquero. No es exposición "abierta", es endurecimiento de defensa en profundidad.
4. Cliente requiere reescribir 8 sitios — riesgo de regresión a 5 días del deadline.

Decisión: documentar como limitación v1.0 y traer si reinvierte. Ver `[[plan-release-25may]]` y `[[security-hardening-roadmap]]` punto 1.
