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

### #4 — Hash bcrypt + sal en password recolector (DIFERIDO post-25-may)
Refactor grande del flow de auth recolector. Para 5-20 banqueros de confianza el SHA-256 actual es aceptable; sería must si vas a 100+ usuarios públicos.

### #5 — F3 escritura money 100% server-side (DIFERIDO post-25-may)
8 RPCs nuevas para ajustes de fondo/borrados/etc. Cierre ya está server. Beneficio marginal vs esfuerzo en 4 días.

---

## 📝 Notas operativas

- **Repo:** https://github.com/rubielfernandez2015-glitch/pick3diarias
- **Prod:** https://picks3.vercel.app
- **Server local:** `node _localserver.mjs` → http://localhost:8080
- **Banca de prueba real:** código `D3MYX` (Rubiel/e4f51e2d)
- **Recolector de prueba:** `lourdes`
