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

### 3. §1 Aislamiento multi-banca con signup nuevo
**Esfuerzo:** ~10 min + cleanup. **Riesgo:** bajo (crear + borrar banca de prueba).

Última prueba del checklist sin tachar. Confirma que es realmente multi-banquero seguro:

- [ ] Crear banca temporal con email descartable (signup nuevo).
- [ ] Login con esa banca → NO debe ver datos de Rubiel (jugadas, clientes, resultados, fondo).
- [ ] Borrar al final con DO block scoped (mismo patrón usado en Etapa 3).

---

### 4. Realtime subscription a `resultados` (notificaciones server → cliente sin polling)
**Esfuerzo:** ~45 min. **Riesgo:** bajo (canal aditivo, no cambia lógica).

Reportado 2026-05-21: al revertir un cierre desde la web, la PWA en background tarda en reflejarlo hasta que vuelve al foco (sin `visibilitychange` no hay disparo). Workaround actual: actualizar manualmente la PWA.

**Solución:** suscribirse a cambios de `public.resultados` filtrados por `banquero_id` via Supabase Realtime. Cualquier INSERT/UPDATE/DELETE → `resyncEstado()` automático sin necesidad de foco/polling. La app ya tiene una variable `rts` declarada (ver `logout` que la limpia); falta cablear la suscripción en `login` y en el handler.

```js
rts = sb.channel('resultados-'+banqueroId)
  .on('postgres_changes', {event:'*', schema:'public', table:'resultados',
       filter:'banquero_id=eq.'+banqueroId}, () => resyncEstado())
  .subscribe();
```

Beneficio extra: también se reflejaría en tiempo real cualquier cambio hecho desde otra pestaña/dispositivo sin esperar al `visibilitychange`.

---

## 🟡 v1.1 — Etapa 2: endurecer lecturas anon

**Esfuerzo:** ~2.5 hs dedicadas. **Riesgo:** medio (reescribir 8 sitios en `index.html`, requiere validación cuidadosa).

Plan completo en `PLAN_ETAPA2_endurecer_anon.md`.

Resumen:
- 2 RPCs nuevas: `banca.recolector_resultados(p_token, p_fechas, p_sesiones)` y `banca.recolector_clientes(p_token, p_q)`.
- Reescribir 8 sitios donde el recolector lee directo `public.resultados`/`public.clientes`.
- `REVOKE SELECT ON public.resultados/clientes FROM anon` al final.
- Validar en localhost antes de revocar.

**Mitigación actual** (por qué se difirió): la `publishable key` no expone `service_role`; lo único leíble cross-banca son nombres de clientes y números/picks de otras bancas vía API si alguien conoce el endpoint exacto. **Sin riesgo financiero** (la tabla `jugadas` ya está aislada por banca).

---

## 🔴 v1.1+ / v2 — más adelante

| # | Item | Por qué se difiere |
|---|---|---|
| 4 | F3 escritura money 100% server-side (≈8 RPCs) | Cierre ya está en servidor (Punto 4 F2); beneficio marginal vs esfuerzo |
| 5 | Hash bcrypt + sal en contraseña recolector | Hoy SHA-256 client-side; requiere refactor Auth completo (v2) |
| 6 | Auditoría a prueba de manipulación | Hoy `audit()` inserta como anon; mover a RPC SECURITY DEFINER |
| 7 | Migraciones SQL versionadas en repo | Hoy schema/RPCs/policies viven solo en Supabase; sin versionado |

---

## 📝 Notas operativas

- **Repo:** https://github.com/rubielfernandez2015-glitch/pick3diarias
- **Prod:** https://picks3.vercel.app
- **Server local:** `node _localserver.mjs` → http://localhost:8080
- **Banca de prueba real:** código `D3MYX` (Rubiel/e4f51e2d)
- **Recolector de prueba:** `lourdes`
