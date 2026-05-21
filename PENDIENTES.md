# 📋 Pendientes post-release v1.0.0

**Última actualización:** 2026-05-21 · **Release actual:** `v1.0.0` (commit `6c63131`)

> La app está oficialmente en producción multi-banquero. Esta lista es el roadmap de lo que queda — nada acá bloquea el uso normal.

---

## 🟢 Quick wins (sesión corta, ~30 min en total)

### 1. §6 Re-sync entre 2 pestañas
**Esfuerzo:** 5 min de prueba. **Riesgo:** ninguno (el código ya está).

Probar que el handler `visibilitychange`/`focus`/`pageshow` (commit `47d9f10`) sigue funcionando bien tras los cambios de Etapa 4:

- [ ] Abrir 2 pestañas como admin. Aplicar cierre en pestaña B → volver a pestaña A → banner/registro se actualizan solos sin F5.
- [ ] Cerrar todas las pestañas, abrir nueva → carga estado correcto.
- [ ] PWA en background 5 min → traer al frente → re-sync.

### 2. UX: panel "Copiar" del Resumen no colapsa al cambiar tab
**Esfuerzo:** ~15 min de código + prueba. **Riesgo:** bajo (UX puro, no toca cálculo).

Bug reportado 2026-05-20: en tab Resumen, expandir panel "copiar" → copiar texto → cambiar de tab y volver → el panel sigue desplegado hasta F5.

**Fix probable:** en `showTab`, si se sale del tab Resumen, resetear el `display:none` del panel desplegado. O bien, al entrar al tab Resumen, colapsar el panel por defecto.

### 3. §1 Aislamiento multi-banca con signup nuevo
**Esfuerzo:** ~10 min + cleanup. **Riesgo:** bajo (crear + borrar banca de prueba).

Última prueba del checklist sin tachar. Confirma que es realmente multi-banquero seguro:

- [ ] Crear banca temporal con email descartable (signup nuevo).
- [ ] Login con esa banca → NO debe ver datos de Rubiel (jugadas, clientes, resultados, fondo).
- [ ] Borrar al final con DO block scoped (mismo patrón usado en Etapa 3).

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
