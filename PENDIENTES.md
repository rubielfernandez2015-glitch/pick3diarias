# 📋 Pendientes post-release v1.0.0

**Última actualización:** 2026-05-21 · **Release actual:** `v1.0.0` (commit `6c63131`)

> La app está oficialmente en producción multi-banquero. Esta lista es el roadmap de lo que queda — nada acá bloquea el uso normal.

---

## 🟢 Quick wins (sesión corta, ~30 min en total)

### 1. §6 Re-sync entre 2 pestañas — ✅ VALIDADO 2026-05-21

Funciona cross-pestaña y cross-dispositivo (PWA): tocar Resultado en una pestaña ya muestra el cambio sin F5; revertir desde la app móvil refleja en pestaña web casi al instante.

### 2. UX polish — estado local que no se resetea al cambiar contexto — ✅ HECHO 2026-05-21
**Triple fix aplicado y validado en localhost (cross-pestaña):**
- `showTab` ahora colapsa `#RES-share-preview` al cambiar de tab.
- `loadResG` limpia `#IRES.value` también cuando no hay resultado en sesión día (antes solo en noche).
- `resyncEstado` llama `vistaR()` si el tab activo es Resultado (refresca sin esperar cambio de tab manual).

Residual observado por usuario: cuando revierte un cierre desde la web, la PWA en background tarda en reflejarlo hasta que vuelve al foco. Es esperable (sin `visibilitychange` no hay disparo). Solución limpia → ver item 4 abajo (Realtime).

### 3. §1 Aislamiento multi-banca con signup nuevo — ✅ VALIDADO 2026-05-21

Banca de prueba `BancaTest`/`55SMP` (uid `f3ffb478-...`) creada con `rubielfernandez2015+aisla@gmail.com`. Recorridos los 9 tabs admin: TODOS vacíos, cero data cruzada de Rubiel. Cleanup atómico ejecutado en 8 pasos (banca + public + auth.users); verificación post-cleanup confirma que solo queda Rubiel/D3MYX. La app es realmente multi-banquero segura.

**Bug encontrado al validar:** `verificarHuerfanasPostCierre` usaba `created_at` en `public.resultados` cuando la columna se llama `ts` → HTTP 400 silencioso, la detección de huérfanas post-cierre nunca funcionó. Fix commit `8a30b22`. Mismo patrón a buscar en otros lugares si reaparece.

---

### 4. Realtime subscription — ✅ VALIDADO 2026-05-21

Diagnóstico: la suscripción cliente (`startRT` línea 2589) YA existía y estaba bien armada para `jugadas` y `resultados`. El problema era **server-side**: la `publication supabase_realtime` estaba vacía → ningún cambio se propagaba.

Fix en Supabase (3 SQLs):
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.jugadas;
ALTER PUBLICATION supabase_realtime ADD TABLE public.resultados;
ALTER TABLE public.jugadas    REPLICA IDENTITY FULL;
ALTER TABLE public.resultados REPLICA IDENTITY FULL;
```

Validado en vivo: cierre/revertir en pestaña A → pestaña B y PWA en otro dispositivo reflejan el cambio en 1-2s sin foco/F5. Cero código cambiado en `index.html`.

---

## 🟡 v1.1 — Etapa 2: endurecer lecturas anon — ✅ FASES A-G COMPLETAS 2026-05-21

**Estado:** cliente recolector ya NO depende de SELECT directo a `public.resultados`/`public.clientes` salvo como fallback de emergencia. Falta solo el REVOKE final (diferido por seguridad).

### ✅ Fase A — RPCs creadas
- `banca.recolector_resultados(p_token uuid, p_fechas text[], p_sesiones text[])` — SETOF resultados, valida token + filtra por banca.
- `banca.recolector_clientes(p_token uuid, p_q text, p_limit int)` — autocompletado con LIKE, excluye `__FONDO*__`.
- Patrón calcado de `banca.acumulados_recolector` (existente en prod, funciona).

### ✅ Fase B — RPCs validadas con queries directas
- count=28, filtros por fecha OK, autocompletado P→Pedro/Piti/Profe OK, token inválido → `TOKEN_INVALIDO`.

### ✅ Fases C-G — 7 sitios cliente reescritos con fallback
Cada sitio: si `rol==='recolector'&&recToken` → intenta RPC, si falla cae al SELECT directo (que sigue funcionando hoy). Admin no se tocó. Flag `rpcOK` explícito para evitar fallback redundante.

| Sitio | Función | Commit |
|---|---|---|
| 1 | `doAC` autocomplete clientes | `8b00b71` |
| 2 | `isSesionCerrada` hot-path | `64b2a2e` |
| 3 | `loadResR` resultado del día | `081a56f` |
| 4 | `loadHist` rama recolector | `cc33776` |
| 5 | `togHistRec` detalle día expandido | `0ef4f5d` |
| 6+7 | `loadGR` (resH + sesGR) | `f23adf9` |

### ✅ Fase H — REVOKE ejecutado 2026-05-21

```sql
REVOKE SELECT ON public.clientes   FROM anon;
REVOKE SELECT ON public.resultados FROM anon;
```

Verificación: `anon` ya NO tiene `SELECT` en ninguna de las 2 tablas (solo INSERT/UPDATE/DELETE/etc., que igual quedan bloqueados por RLS sin `auth.uid()`). La única vía de lectura para el recolector es vía RPC `banca.recolector_resultados` y `banca.recolector_clientes` (token-aware, filtrado por banca server-side).

**Rollback de emergencia** (si en los próximos días apareciera algo roto en uso real):
```sql
GRANT SELECT ON public.clientes   TO anon;
GRANT SELECT ON public.resultados TO anon;
```
Esto reactiva el fallback de los 7 sitios cliente y restaura el comportamiento previo al REVOKE mientras se investiga.

**Etapa 2 100% cerrada.** Última fuga de lectura cross-banca cubierta.

---

## 🎯 Roadmap priorizado hasta 2026-05-25 (deadline duro)

Orden de ataque acordado 2026-05-21. Trabajamos uno por uno, validando en localhost antes de prod.

### #1 — Auditoría a prueba de manipulación — ✅ CERRADA 2026-05-21

Antes: `audit()` cliente insertaba como `anon` con `banquero_id` y `recolector_id` enviados por el cliente. Cualquiera con la publishable key podía inyectar entradas falsas vía POST anon.

Ahora:
- RPC `public.audit_log(p_accion, p_detalle, p_recolector_id, p_token)` SECURITY DEFINER. Si llega con `p_token` → valida via `banca._rec_por_token` y deriva `banquero_id` + `recolector_id` REALES desde BD. Si no → usa `auth.uid()` (admin). El cliente **no puede mentir** sobre quién hace la acción.
- `audit()` cliente reescrito para llamar la RPC. Fallback al INSERT directo eliminado por REVOKE (innecesario).
- `REVOKE INSERT ON public.auditoria FROM anon` ejecutado en producción.
- Validado: post-REVOKE, login banquero y login recolector siguen registrando 204 OK con identidades server-derivadas correctas.

Commit principal: `1ded592`. Bonus: durante el debug se descubrió un bug de timing en los 7 sitios de Etapa 2 (condición `rol==='recolector'&&recToken` fallaba durante restore post-F5). Fix uniformado a `if(recToken)` en los 7 sitios.

### #2 — Recuperación de password del recolector — ✅ CERRADA 2026-05-21

Estado descubierto al auditar:
- **Recolector cambia su propia clave** (boton 🔑 header) → estaba ROTO silencioso: hacia UPDATE directo a `banca.recolectores` como anon, RLS bloqueaba pero Supabase no devolvia error → toast decia OK pero la clave no cambiaba → al loguear con la nueva no entraba. **Bug real en produccion**.
- **Banquero resetea clave de recolector** (Equipo → 🔑 Pass) → funcionaba OK (admin tiene auth.uid()).
- **Recolector olvidó su clave** (no logueado) → SIN UI, sin guia, quedaba bloqueado sin saber a quien pedir ayuda.

Fixes:
- RPC `banca.cambiar_password_recolector(p_token uuid, p_nueva_hash text)` SECURITY DEFINER. Valida el token via `_rec_por_token`, actualiza SOLO la fila del recolector autenticado. Commit `d75df66`.
- Cliente `cambiarPass` reescrito para usar la RPC.
- Mensaje informativo en login al seleccionar rol "Recolector": guia a contactar al banquero (Equipo → 🔑 Pass). Commit `40cb444`.

Validado en localhost: cambio + logout + login con nueva clave = entra. Restauracion OK. Mensaje en login se muestra/oculta correctamente al alternar roles.

### #3 — Migraciones SQL versionadas en repo — ✅ CERRADA 2026-05-21

Creada carpeta `/migrations/` con baseline completo del estado actual de Supabase. Antes el schema/RPCs/policies/publication vivían solo en el dashboard de Supabase — sin disaster recovery posible. Ahora todo está versionado en el repo.

Archivos:
- `README.md` — explicación, tabla de RPCs, instrucciones de recovery.
- `00_baseline_functions.sql` — 25 funciones (RPCs + helpers + triggers) con sus GRANT EXECUTE.
- `00_baseline_policies.sql` — RLS policies de 11 tablas. Marca como ⚠️ DEPRECATED las 3 policies "acceso total" legacy.
- `00_baseline_grants.sql` — REVOKEs aplicados (Etapa 2 + Auditoría) y recomendaciones de hardening adicional.
- `00_baseline_realtime.sql` — ALTER PUBLICATION + REPLICA IDENTITY FULL.

Para cambios futuros: archivos numerados `NNN_descripcion.sql`. Patrón documentado en README.

Commit `115cc42`.

### Hardening bonus — ✅ CERRADO 2026-05-21

Tras los 3 items principales, se ejecutaron 3 mejoras documentadas en `migrations/00_baseline_*.sql`:

- **DROP de 3 policies "acceso total" legacy** (clientes, limites_numeros, resultados): eran inertes por los REVOKEs de Etapa 2 pero peligrosas si alguien re-grant a anon.
- **REVOKE ALL FROM anon en 4 tablas admin-only**: banquero_ajustes, fondo_movimientos, limites_numeros, comision_historial. Defensa en profundidad (antes solo RLS las cubría).
- **REVOKE ALL FROM anon en ganancias_recolector** + eliminación del form "Agregar Comisión Anterior" del recolector que estaba silent-broken. Si se necesita agregar acumulado manual: SQL directo. Commit `e67518c`.

### #4 — Hash bcrypt + sal en password recolector (DIFERIDO con criterio)

**Estado hoy:** SHA-256 sin sal calculado client-side. Aceptable para 5-20 banqueros de confianza.

**Cuándo SÍ aplicarlo (triggers concretos):**
- Si la BD llega a **50+ recolectores totales** (sumando todas las bancas).
- Si la BD llega a **20+ banqueros distintos** (aumenta superficie de ataque).
- Si vas a hacer público el signup sin moderación (cualquiera puede crear cuenta).
- Si tenés una sospecha o un evento real de password leak/intento de brute force.

**Por qué importa con muchos usuarios:**
- SHA-256 sin sal es vulnerable a **rainbow tables** (tablas pre-computadas de hashes comunes).
- Si alguien logra leer la tabla `banca.recolectores` (por bug RLS, dump de Supabase, lo que sea), puede crackear claves débiles en segundos.
- Con bcrypt + sal: cada hash es único aunque la clave sea la misma. Las rainbow tables se vuelven inútiles. El brute force pasa de "millones por segundo" a "decenas por segundo".

**Esfuerzo real:** 1-2 días bien hechos.
1. Habilitar `pgcrypto` en Supabase (si no está): `CREATE EXTENSION IF NOT EXISTS pgcrypto;`
2. Agregar columna `password_hash_bcrypt` a `banca.recolectores` (mantener la vieja durante migración).
3. Reescribir `banca.login_recolector` y `banca.cambiar_password_recolector` para usar `crypt(password, password_hash_bcrypt)` y verificar con `crypt(input, stored_hash) = stored_hash`.
4. **Grace period**: en `login_recolector`, si NO hay bcrypt hash pero sí SHA-256, validar con SHA-256 y AL MISMO TIEMPO migrar a bcrypt (`UPDATE ... SET password_hash_bcrypt = crypt(password, gen_salt('bf'))`). Después de N días, drop columna vieja.
5. Cliente: dejar de hashear con SHA-256, mandar el password en plain text (vía HTTPS, protegido por TLS) — bcrypt corre en BD.
6. Validar que login + cambio de password funcionan post-migración.

---

### #5 — F3 escritura money 100% server-side (DIFERIDO con criterio)

**Estado hoy:** cierre y cálculo de fondo son 100% server-side (Punto 4 F2 cerrado). Lo que aún parte del cliente:
- Ajustes manuales del fondo (`fondo_movimientos.insert`).
- Borrado de jugadas / días / meses (`delJ`, `delAll`, `eliminarDiaCompleto`, `borrarMes`).
- Edición de `__FONDO_BASE__` / `__FONDO_ACUM__` (`saveFoBase`, `saveFoAcum`).
- Reversión de cierres (`revertirCierre`).

**Por qué hoy es aceptable:**
- Esas escrituras requieren JWT admin (`auth.uid()`) — RLS las acota a la propia banca.
- 26 queries auditadas con `banquero_id` explícito como defensa en profundidad (Etapa 4).
- No hay vía para que un banquero modifique la banca de otro.

**Cuándo SÍ aplicarlo (triggers concretos):**
- Si surge un **bug real donde un cliente comprometido escribe valores incorrectos** (ej. XSS, extensión del browser, plugin malicioso).
- Si necesitás **logs server-side inviolables** de cada modificación de fondo (auditoría avanzada).
- Si planeás integraciones con sistemas externos donde el cliente no sea de confianza (API pública, white-label, etc.).
- Si el equipo crece y querés que la lógica financiera viva en un solo lugar (server), no esparcida en JS cliente.

**Por qué con muchos banqueros importa más:**
- Con 200 banqueros, la probabilidad de uno con dispositivo comprometido aumenta.
- Errores cliente afectan solo a su propia banca (RLS protege a otros), pero el banquero afectado puede perder mucho dinero.
- Auditoría centralizada server-side es más fácil de mantener y revisar.

**Esfuerzo real:** 2.5-4 hs si va perfecto, 6-8 hs si surgen edge cases.
- 8 RPCs nuevas: `banca.guardar_fondo_base`, `banca.guardar_fondo_acum`, `banca.ajustar_fondo`, `banca.borrar_jugada`, `banca.borrar_jugadas_seleccionadas`, `banca.eliminar_dia`, `banca.borrar_mes`, `banca.revertir_cierre`.
- Cada una valida `auth.uid()` y opera en transacción atómica con `recalcFondo` server-side.
- Reescribir ~8 sitios cliente para usar las RPCs.
- `REVOKE INSERT/UPDATE/DELETE FROM authenticated` en las tablas afectadas — solo via RPC.
- Validar A/B (totales pre/post cambio idénticos).

---

## 🎯 Decisión estratégica recomendada según escala futura

| Escala esperada | #4 bcrypt | #5 F3 money server | Otros |
|---|---|---|---|
| **5-10 banqueros conocidos** (caso actual) | ❌ No urgente | ❌ No urgente | App está OK |
| **20-50 banqueros** | ⚠️ Recomendado | ❌ Diferir | Hacer bcrypt |
| **50-100 banqueros** | ✅ **Obligatorio** | ⚠️ Recomendado | Hacer ambos |
| **100+ banqueros públicos** | ✅ Obligatorio | ✅ Obligatorio | + Monitoring, rate limit, etc. |

**Si llegás a 200 banqueros:** hacer #4 + #5 + considerar (a) rate limiting en login_recolector, (b) email/SMS 2FA para banqueros, (c) logging avanzado con alertas (Sentry/Datadog), (d) backups automáticos diarios de Supabase.

---

## 📝 Notas operativas

- **Repo:** https://github.com/rubielfernandez2015-glitch/pick3diarias
- **Prod:** https://picks3.vercel.app
- **Server local:** `node _localserver.mjs` → http://localhost:8080
- **Banca de prueba real:** código `D3MYX` (Rubiel/e4f51e2d)
- **Recolector de prueba:** `lourdes`
