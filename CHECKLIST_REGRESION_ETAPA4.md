# ✅ CHECKLIST REGRESIÓN FINAL — Etapa 4

**Fecha:** 2026-05-20 · **Deadline release:** 2026-05-25 · **Tag candidato:** `v1.0.0`

> Marcá cada ítem con ✔ / ✖ a medida que probás. **Lo que falle al final del día → me lo pasás como lista y lo arreglamos antes del tag.**
> Probar en **localhost** primero (servidor `_localserver.mjs` :8080) salvo donde diga "prod" explícito.
> **Este archivo es la fuente única — todo lo que tenés que probar está acá.** Las cosas nuevas de hoy están marcadas con 🆕. Lo crítico (bug confirmado del doble-cierre que sobreescribía con 0s) con 🔥.

---

## 0. Setup previo (1 min)
- [ ] `node _localserver.mjs` corre en :8080 (o el server local que uses).
- [ ] Abrir http://localhost:8080 en una ventana normal y otra de incógnito.
- [ ] Tener a mano la BD real (banca de prueba `e4f51e2d` / código `D3MYX`).

---

## 1. LOGIN / LOGOUT (5 min)

### Admin (banquero)
- [ ] Login con email+contraseña de Rubiel → entra a Resumen.
- [ ] Contraseña mal → mensaje de error claro, no entra.
- [ ] Logout → vuelve a pantalla de login limpia, sin restos de sesión.
- [ ] Reload tras login → mantiene sesión.

### Recolector
- [ ] Login con código `D3MYX` + `lourdes` + clave → entra.
- [ ] Código mal → "Código de banca, usuario o contraseña incorrectos" (genérico, sin enumerar cuál falló).
- [ ] Clave mal → mismo mensaje genérico.
- [ ] Logout → pantalla de login con código prellenado (b_reccod en localStorage).
- [ ] Reload tras login → mantiene sesión.

### Aislamiento multi-banca (anti-fuga)
- [ ] Crear una banca temporal de prueba (signup nuevo con email descartable) → al login NO ve datos de Rubiel (ni jugadas, ni clientes, ni resultados, ni fondo).
- [ ] **Al final borrar esa banca de prueba** (DO block scoped igual que Etapa 3).

### Admin↔recolector mismo dispositivo
- [ ] En la misma ventana: login admin → logout → login recolector → entra sin necesidad de cerrar/reabrir el navegador.
- [ ] Login recolector → logout → login admin → entra.

---

## 2. REGISTRO DE JUGADAS (10 min)

### Como Recolector
- [ ] Registrar jugada con cliente NUEVO → aparece en "Jugadas Pendientes" con badge 🌅/🌙 correcto.
- [ ] Registrar jugada con cliente EXISTENTE → autocomplete sugiere nombres reales (PROFE, etc.), **no** lista vacía (BUG #3 ya arreglado).
- [ ] Registrar con monto 0 / monto negativo → rechaza.
- [ ] Borrar una jugada propia → se va del listado.
- [ ] Anti-trampa: a partir de 1:30 PM ET sin resultado aplicado → banner "⛔ Registro en pausa — esperando resultado del Día", **sin botón Desbloquear** (oculto al recolector).

### Como Admin
- [ ] Registrar jugada a nombre de un recolector → aparece bajo ese recolector.
- [ ] Selector de fecha — fecha alterna (sigDia o anterior huérfana).
- [ ] 🆕 **Desbloquear durante corte:** banner en pausa → tocar "Desbloquear" → empezar a escribir nombre cliente → abrir calculadora del Windows / Alt+Tab → volver → **el banner sigue oculto y el campo sigue habilitado**.
- [ ] 🆕 Repetir el ciclo arriba 3 veces → no se re-bloquea.
- [ ] 🆕 Si admin aplica el resultado del día → el flag se invalida solo (próxima vez que aparezca el corte de noche, debe bloquear normal).

---

## 3. CIERRE DE SESIÓN (10 min)

### Cierre día con resultado manual
- [ ] Como admin: tab Resultado → ingresar 3 dígitos → Aplicar → modal de confirmación con fecha correcta ("Resultado del [hoy]"), sin banner rojo de discrepancia.
- [ ] Tras confirmar: cierre se ejecuta server-side, fondo actualizado, jugadas movidas a `dia_cierre=hoy`.
- [ ] Resumen post-cierre muestra: Rec total, Premios, Comisión total, Ganancia banquero, Fondo actualizado.
- [ ] Desglose por recolector usa **comisión real** (no fallback 15%) — bug #4 ya arreglado.

### Cierre día con Buscar Resultado (auto)
- [ ] Tab Resultado → "Buscar Resultado Automático" → trae número de smooth-api / caché.
- [ ] Modal confirmación muestra fecha ISO correcta del resultado.
- [ ] Si la fecha del resultado ≠ hoy → banner rojo + botón "⚠️ Cerrar igual".

### Cierre noche
- [ ] Activar `sesion_noche` para un recolector → admin ve banner Noche tras aplicar resultado día.
- [ ] Registrar jugadas noche → cerrar con número noche → mismo flujo.
- [ ] Revertir cierre noche → jugadas vuelven a pendientes, fondo restaurado.

### Revertir
- [ ] Cierre día aplicado → tocar ↩ Revertir → jugadas pendientes restauradas, fondo restaurado, ganancia recolector borrada.

---

## 4. HISTORIAL Y REPORTES (10 min)

### Historial admin
- [ ] Una fila por día con badges 🌅/🌙 (ambas sesiones si hay).
- [ ] Expandir día → detalle separado por sesión: 🌅 Día N°/Pick + ganadores · 🌙 Noche N°/Pick + ganadores.
- [ ] Total comisión, rec, premios coherente por día.

### Historial recolector
- [ ] Una fila por día (no dos cuando hay día+noche).
- [ ] Números mostrados: `🌅146 · 🌙033` formato.
- [ ] Expandir día → detalle por sesión con ganadores resaltados.

### Ganancias
- [ ] Admin tab Ganancias: gráfica/lista por día con neto correcto.
- [ ] Recolector tab Ganancias: Rec Hoy, Premios Hoy, Comisión Hoy + acumulado.
- [ ] Agregar comisión anterior → suma al acumulado, queda en historial de comisiones.

### Resumen (admin)
- [ ] Cifras del día actual coherentes con Jugadas Pendientes.
- [ ] Equipo: tarjetas con datos por recolector (no mezcla bancas).

### Números (admin)
- [ ] Vista hoy / fecha alterna funciona.
- [ ] Límites específicos: agregar/borrar uno, persiste.

### Fondo
- [ ] Fondo base + acumulado + Σganancia = total mostrado.
- [ ] Editar base/acumulado → guarda, total se recalcula.

### Exportar
- [ ] Generar reporte WhatsApp del día → texto correcto, sin HTML escapado raro.

### Ajustes
- [ ] Muestra "Código de tu banca: D3MYX".
- [ ] Cambiar nombre del banquero → persiste tras reload.

---

## 5. ANTI-TRAMPA / CORTE DE REGISTRO (5 min)

- [ ] Antes de 1:30 PM ET: registro abierto, sin banner.
- [ ] A partir de 1:30 PM ET sin resultado aplicado: banner "Registro en pausa". Recolector bloqueado total. Admin ve botón Desbloquear.
- [ ] Tras aplicar resultado día sin recolectores noche: registro abierto, DCBX "Día completado · Jugadas → mañana".
- [ ] Tras aplicar resultado día con recolectores noche: registro abierto, DCBX "Jugadas → Sesión Noche".
- [ ] A partir de 9:35 PM ET sesión noche sin resultado: banner cierre noche.
- [ ] Tras aplicar resultado noche: DCBX "Día completado".

---

## 6. RE-SYNC AL VOLVER (3 min) — commit 47d9f10

- [ ] Pestaña 1 admin, pestaña 2 admin: en pestaña 2 aplicar resultado → volver a pestaña 1 → banner/registro se actualizan solos sin recargar.
- [ ] Cerrar pestaña, abrir nueva → carga el estado correcto.
- [ ] PWA en background → traer al frente → re-sync.

---

## 7-bis. ANTI-DOBLE-SUBMIT + GUARDA DE SOBREESCRITURA (5 min) 🆕🔥

**BUG REAL confirmado 2026-05-19 por el usuario:** doble-click en Aplicar disparaba 2 cierres; el 2do encontraba 0 jugadas pendientes (ya cerradas), calculaba totales=0 y **sobreescribía la fila real en `resultados` con ceros** → datos perdidos.

Triple defensa aplicada:
1. **`_applyBusy`** — el 2do click se ignora en el mismo dispositivo.
2. **Botón "Aplicar" se deshabilita visualmente** mientras procesa.
3. **Guarda pre-RPC** — antes de llamar `cerrar_sesion`, verifica si ya hay resultado para esa (fecha,sesión,banquero); si existe, NO dispara el RPC. Cubre el caso de 2 dispositivos.

### Pruebas:
- [ ] Tab Resultado → ingresar número → tocar **"Aplicar" 3 veces seguidas rápido** → solo se cierra 1 vez. Verifica en la BD (`SELECT * FROM resultados WHERE fecha=hoy`) que `total_rec`, `comision_rec`, `ganancia_banquero` tienen valores reales (no 0).
- [ ] Tras cierre exitoso → volver a tocar "Aplicar" con el mismo número → toast "Este día ya está cerrado con el número XXX". `resultados` NO se reescribe con 0s.
- [ ] Tras cierre exitoso → cambiar el número en el input → tocar "Aplicar" → toast "Día ya cerrado con número YYY. Usa ↩ Revertir antes de cambiar." NO se reescribe.
- [ ] Revertir cierre → volver a aplicar (mismo o distinto número) → ahora SÍ cierra normal.
- [ ] Tocar **"↩ Revertir" 3 veces rápido** → solo revierte 1 vez (botón deshabilitado).
- [ ] (Opcional, requiere 2 dispositivos): Aplicar resultado desde teléfono A y casi simultáneamente desde PC → solo uno cierra; el otro recibe toast "ya cerrado".

## 7-ter. AUDITORÍA EXHAUSTIVA MULTI-BANCA (10 min) 🔥🆕

Sweep completo: **26 queries arregladas** (deletes + selects + upserts + inserts + 1 UUID hardcodeado eliminado). Después del sweep el script de verificación reporta **0 queries críticas sin filter por banca**. Lo más impactante:

### Crítico: UUID de Lourdes hardcodeado en `loadGR` 🔥
Antes: `const esLourdes=myRec==='9c9cf2ae-...';` → SOLO Lourdes veía sus acumulados manuales ("Agregar Comisión Anterior"). Cualquier otro recolector NUNCA los veía. Y la query subyacente no filtraba por banca.
Ahora: todos los recolectores ven los acumulados manuales DE SU PROPIA BANCA.
- [ ] Como admin, en tab Recolector "Lourdes" tocar "Agregar Comisión Anterior" → registrar 50 CUP con nota "Test". Login como Lourdes → tab Ganancias → ese registro aparece en el historial de comisiones. ✓
- [ ] Si tenés un 2do recolector en la misma banca, crearle un acumulado manual → ese 2do recolector también lo ve (antes NO lo veía).

### Cliente upsert con banca + onConflict
- [ ] Registrar jugada con cliente nuevo "TESTBANCA1" → aparece en autocomplete propio.
- [ ] (Si tenés acceso a otra banca): registrar jugada con cliente "TESTBANCA1" en la otra banca → ambas mantienen su propio "TESTBANCA1" en `clientes`, sin pisarse.

### Registro: bloqueo por fecha con resultado debe ser POR BANCA
- [ ] En tu banca: aplicar resultado del día → como admin de ESA banca: no podés registrar más jugadas para ese día (esperado).
- [ ] (Si tenés acceso a otra banca): en la otra banca, esa misma fecha NO debe estar bloqueada (antes el bug bloqueaba si CUALQUIER banca tenía resultado en esa fecha).

### Selector de fechas pendientes / modal huérfanas
- [ ] Selector de fechas para Resultado solo muestra huérfanas de TU banca.
- [ ] Modal "Hay jugadas pendientes de días anteriores" solo cuenta las TUYAS.

### Defensa contra sesión rota
- [ ] Si por algún error `banqueroId` no carga, las funciones críticas (delAll, hDelAll, borrarMes, dlC, getDiaFiltrado, intentarAutoFetch) abortan con toast "Sesión sin banquero" en vez de operar cross-banca.

### Sweep automatizado para verificar
- [ ] (Opcional, para vos verificar): después de bajar el código nuevo, correr este check en consola del navegador no es trivial — pero podés correr esto en la terminal local:
  ```
  grep -nE "sb\.from\('(jugadas|resultados|clientes|fondo_movimientos|ganancias_recolector|limites_numeros|banquero_ajustes|auditoria)'\)" index.html | grep -v banquero_id
  ```
  Debe dar 0 resultados (o solo líneas donde el `banquero_id` está en línea siguiente — confirmar visualmente).

## 7. FLASH AL CAMBIAR TABS — RECOLECTOR (2 min) 🆕

- [ ] Recolector: estar en Resultado → cambiar a Historial → **NO ver datos viejos del cierre**, sino "⏳ Cargando…" hasta que termine.
- [ ] Cambiar a Ganancias → stats muestran "…" hasta que cargan (no valores pre-cierre).
- [ ] Cambiar a Registrar → "Cargando…" en jugadas pendientes hasta que llega `loadJ`.

---

## 8. PWA / DESPLIEGUE (3 min)

- [ ] En prod (https://picks3.vercel.app) → reload normal → trae versión publicada.
- [ ] PWA instalada → cerrar y reabrir → no queda colgada en versión vieja indefinidamente (SW debe refrescar).
- [ ] Modo offline: cola local de jugadas pendientes sigue funcionando; al reconectar, se sincronizan.

---

## 9. BASE DE DATOS — VERIFICACIONES SQL (opcional, 3 min)

```sql
-- 1. Recolector solo ve su banca (verificación de aislamiento):
SELECT count(*) FROM public.jugadas WHERE banquero_id IS NULL; -- esperado: 0
SELECT count(*) FROM banca.recolectores WHERE banquero_id IS NULL; -- esperado: 0

-- 2. RLS activa en tablas críticas:
SELECT relname, relrowsecurity FROM pg_class
 WHERE relname IN ('jugadas','resultados','clientes','fondo_movimientos','ganancias_recolector',
                   'banqueros','recolectores','recolector_sesiones');
-- todas: relrowsecurity=true

-- 3. Política "acceso total" NO debe existir en jugadas:
SELECT polname FROM pg_policy WHERE polrelid='public.jugadas'::regclass;
-- esperado: solo jugadas_banquero
```

---

## 10. LISTA DE BUGS CONOCIDOS / LIMITACIONES v1.0

Documentar al final del día qué queda como "limitación conocida" para no bloquear el release:

- [ ] Etapa 2 (lecturas anon directas a `resultados`/`clientes`): la app funciona y jugadas está aislada por banca; solo nombres y números cross-banca leíbles vía API pública. **Mitigación:** la `publishable key` no expone el `service_role`; un atacante necesita la URL exacta + endpoint correcto. Diferido a v1.1.
- [ ] F3 escritura money (RPCs server-side blindados): diferido post-release.
- [ ] Hash bcrypt + sal: hoy SHA-256 sin sal en cliente. Diferido.
- [ ] Auditoría a prueba de manipulación: hoy `audit()` inserta como anon. Diferido.

---

## 7-quater. UX / PERFORMANCE / EDGE CASES (5 min) 🆕

Ronda extra de auditoría: 7 fixes filtrados de 27 hallazgos (descartadas las sobre-estimaciones).

### Performance
- [ ] `tick()` ahora se salta cuando la PWA está minimizada (`document.hidden`) y cuando no hay rol — ahorra batería. Validación: poner la PWA en segundo plano 5 min, traerla al frente, el reloj se actualiza inmediato.
- [ ] `sincronizarCola` ahora envía las jugadas pendientes **en paralelo** (Promise.all) en vez de una por una. Validación: dejar 5+ jugadas en cola offline, volver online, deben sincronizarse en ~1 RTT, no en 5×.
- [ ] `verificarCorteRegistro` (corre cada 60s) ahora aborta si no hay sesión.
- [ ] `logout` ahora limpia `_schedulerInterval` (cierre auto admin), no solo `autoFetchTimer`.

### UX
- [ ] Tab Resultado → ingresar "-5" → toast claro: "Número inválido — solo dígitos 0-999".
- [ ] Ingresar "1234" → toast claro: "Número fuera de rango (máximo 999)".
- [ ] Ingresar "" → "Número inválido — debe ser 000 a 999".

### Edge: "Agregar Comisión Anterior" multi-recolector 🔥
Refactor: ahora cada recolector ve **solo sus propios acumulados manuales** (antes mostraba todos los de la banca mezclados; antes de eso, solo Lourdes los veía por UUID hardcodeado).
- [ ] Hacer login como Lourdes → "Agregar Comisión Anterior" 200 CUP "Test L". Aparece en historial.
- [ ] Si tenés un 2do recolector en la banca: login con ese 2do → no ve los 200 CUP de Lourdes; agregar 100 CUP "Test 2". Vuelve a Lourdes: solo ve sus 200, no los 100 del otro.

### 🚨 MIGRACIÓN SQL OBLIGATORIA antes de validar lo anterior
Los 2 registros legacy de Lourdes están en BD pero invisibles (no tienen `banquero_id` ni `recolector_id`). Corré el script `MIGRACION_acumulados_legacy.sql` en Supabase SQL Editor:
- [ ] Paso 1 (diagnóstico) → confirmá que aparecen los huérfanos.
- [ ] Paso 2 (UPDATE) → "UPDATE 2" (o N huérfanos).
- [ ] Paso 3 (verificación) → no quedan huérfanos.
- [ ] Login como Lourdes en localhost → los 2 acumulados deben volver a aparecer en su historial.

## 11. SI TODO PASA → RELEASE

1. `git add index.html CHECKLIST_REGRESION_ETAPA4.md`
2. `git commit -m "Etapa 4: fixes finales + checklist regresión"`
3. `git push origin main`
4. `git tag -a v1.0.0 -m "Release oficial v1.0.0 — multi-banquero estable"`
5. `git push origin v1.0.0`
6. Verificar en prod: https://picks3.vercel.app cargue versión nueva tras unos minutos.

---

**Tiempo total estimado:** ~50 min de pruebas reales · puede dividirse en 2 tandas.
