# 🎯 La Bolita · Florida Pick 3 — Release Oficial v1.0.0

**Fecha:** 2026-05-25 (objetivo) · **Tag:** `v1.0.0` · **Estado:** primera versión oficial estable multi-banquero.

> **Resumen ejecutivo:** primera release pensada para que la app la use **más de un banquero a la vez** (hasta ~20), con cierre calculado en servidor, anti-trampa por hora, blindaje de fecha del resultado y robustez de banquero nuevo.

---

## Highlights

### 🔐 Multi-banquero real
- **Código de banca** en login del recolector (Etapa 1): cada banca tiene un código corto (ej. `D3MYX`), el recolector entra con código+usuario+clave. Resuelve la ambigüedad cuando 2 bancas usan el mismo nombre de recolector.
- **Aislamiento por banca** activo y blindado en `public.jugadas` (policy `jugadas_banquero` con `auth.uid()` para admin y `app.recolector_id` para recolector vía RPC SECURITY DEFINER; `anon` sin acceso directo).
- **Flujo de banquero nuevo** validado E2E (Etapa 3): signup → red de seguridad en login que garantiza fila `banca.banqueros` + trigger asigna código → estado vacío limpio → fondo/ajustes/recolector/cierre/reportes.
- Pantalla **"¡Cuenta creada!"** post-signup con el código de banca a la vista (Confirm email OFF — recolectores no usan email).

### 💰 Cierre y matemática server-side
- **Cierre calculado en servidor** vía RPC `cerrar_sesion` (Punto 4 F2): cliente solo muestra. Adiós a divergencias entre dispositivos.
- Comisión leída en vivo de `banca.recolectores` al cerrar; cierres previos congelan `comision_rec` en `resultados` (historial inmutable).
- Desglose por recolector lee comisión real directo de la BD (fix bug #4 Etapa 3): se acabaron los "15% por defecto" erróneos.

### 🛡️ Anti-trampa y corte de registro
- Bloqueo automático del registro a partir de la **1:30 PM ET** (corte del sorteo Midday) hasta que el admin aplique el resultado del día. Idem 9:35 PM ET para Noche.
- Recolector **bloqueado total** durante el corte; no ve botón de desbloqueo.
- Admin puede **desbloquear manualmente** si necesita anotar jugadas atrasadas. El desbloqueo aguanta mientras dure el corte actual (entre calculadora ↔ navegador no se rebloquea), se invalida solo cuando el corte termina o cambia (ej. día → noche).

### 🎲 Resultado automático + blindaje de fecha
- Botón "Buscar Resultado" lee de Edge Function `smooth-api` (proxy Jina Reader + caché en `public.resultado_cache`). Sin scraping desde IP Supabase (bloqueada), sin Cowork.
- Cada respuesta incluye **fecha ISO** del resultado. La app muestra "Resultado del [fecha]" y banner rojo si la fecha no coincide con la sesión que estás cerrando.
- Cierre automático **bloquea** si el resultado traído es de otro día (evita aplicar el número de ayer por error).
- Caché auto-sana (fetch fresco sobrescribe); rate-limit Jina mitigado con API key.

### 🔄 Re-sync al volver
- Al cambiar de pestaña / abrir calculadora / volver a la PWA: la app refresca sesión/banner/registro automáticamente (`visibilitychange`/`focus`/`pageshow`).
- Antes: si revertías un cierre en otra pestaña, la primera quedaba con estado viejo.

### 🐞 Bug fixes destacados
- **Cierre huérfano por sesión** (e9b8fb8): si tenías noche del 16 pendiente y cerraste el día del 17, el sistema ya ofrece "Buscar Resultado Noche del 16" sin confundir sesiones.
- **Historial por sesión**: detalle admin y recolector parten día/noche con números, picks y ganadores propios.
- **Autocompletado de clientes** (bug raíz Etapa 3): el filtro `__%` en SQL excluía a TODOS los clientes; arreglado a `\_\_%` literal.
- **Login admin/recolector mismo dispositivo** (Bug A): `signOut({scope:'local'})` antes de RPC recolector → ya no hace falta cerrar/reabrir el navegador.
- **Resync no expulsa al admin desbloqueado** (este release): el flag `_registroDesbloqueado` ya no se reinicia en cada ciclo de `verificarCorteRegistro`; el desbloqueo aguanta toda la pausa.
- **Flash al cambiar tabs en recolector** (este release): los paneles muestran "⏳ Cargando…" en vez de datos viejos del cierre anterior durante los ~3s del fetch.
- **Defensa en profundidad multi-banca** (este release): 6 funciones de borrado (`eliminarDiaCompleto`, `delFoSel`, `delFoTodo`, `delJ`, `delSel`, `descartarHuerfanas`) ahora filtran explícitamente por `banquero_id` además de depender de RLS. Si por cualquier motivo una policy se relajara, los deletes siguen acotados a la propia banca.
- **Anti-doble-submit en cierre y revertido** (este release, **bug real confirmado 2026-05-19**): el doble-click en "Aplicar" disparaba un 2do cierre que encontraba 0 jugadas pendientes y sobreescribía `resultados` con totales=0 — datos reales perdidos. Triple defensa: flag `_applyBusy`/`_revertBusy`, botón deshabilitado mientras procesa, y guarda pre-RPC que verifica si el día ya tiene cierre antes de invocar `cerrar_sesion`. Para cambiar un cierre ahora hay que `↩ Revertir` explícitamente primero.
- **Auditoría exhaustiva multi-banca** (este release): 26 queries en `index.html` que NO filtraban por `banquero_id` ahora lo hacen. Cubre SELECTs, INSERTs, UPDATEs, UPSERTs (con `onConflict` correcto), DELETEs e IN()-cross-fecha en las 8 tablas multi-banca. Resultado del sweep automatizado tras los fixes: **0 queries críticas sin filter de banca**.
- **🔥 UUID hardcodeado eliminado** (este release): el código tenía `const esLourdes=myRec==='9c9cf2ae-…';` que hacía que **solo Lourdes** viera sus acumulados manuales ("Agregar Comisión Anterior"). Cualquier otro recolector NUNCA los veía. Eliminado: ahora cualquier recolector de cualquier banca ve los acumulados manuales de su banca.
- **Bloqueo de registro por fecha era cross-banca**: antes, si CUALQUIER banca tenía resultado en una fecha, el registro para esa fecha se bloqueaba en TODAS las bancas. Arreglado: cada banca tiene su propio gating por fecha.
- **"Agregar Comisión Anterior" ahora discrimina por recolector** (este release, motivado por feedback del usuario): la tabla `ganancias_recolector` no incluía `recolector_id` en las filas manuales — todos los recolectores de una banca veían los acumulados mezclados. Ahora cada `acumulado_previo` se inserta con `recolector_id` y la consulta filtra por él. Las filas legacy se migran con `MIGRACION_acumulados_legacy.sql` (one-shot).
- **Performance PWA** (este release): `tick()` (reloj 1s) deja de actualizar el DOM cuando la pestaña está oculta — ahorro de batería. `sincronizarCola` envía las N jugadas offline pendientes en paralelo (`Promise.all`) en vez de una por una. `logout` limpia `_schedulerInterval` además de `autoFetchTimer`. `verificarCorteRegistro` aborta si no hay sesión.
- **Validación de número en cierre**: input "-5" o "1234" ahora reciben mensaje claro (`Número inválido — solo dígitos 0-999` / `Número fuera de rango (máximo 999)`) en vez de silencio o "Número inválido" genérico.

### 🚀 Performance / latencia
- Cliente: `AbortSignal.timeout(22000)` en `buscarResultadoFlorida` (Edge Function vía Jina + caché tarda ~10s).
- Caché de resultado en BD: 2ª llamada del día devuelve `cache-reciente` instantáneo, sin golpear Jina.

---

## Limitaciones conocidas v1.0 (diferidas a v1.1+)

- **Lectura cross-banca de `resultados` y `clientes` por `anon`**: la app funciona y `jugadas` está blindada por banca; solo nombres y números de otras bancas son leíbles vía API pública (publishable key + endpoint exacto). Sin riesgo financiero — diferido a v1.1.
- **Hash de contraseña recolector**: SHA-256 sin sal en cliente. Diferido (migración a bcrypt/argon2 + Auth completa = v2 si se reinvierte).
- **Auditoría a prueba de manipulación**: hoy `audit()` inserta desde cliente. Diferido.
- **Escritura money 100% server-side** (F3): cierre ya está server, pero registro/borrado/ajustes de fondo aún parten del cliente. Diferido (≈8 RPCs, beneficio marginal con cierre server + aislamiento por banca activo).
- **Migraciones versionadas** en repo: hoy schema/policies/RPCs viven solo en Supabase. Diferido.

---

## Stack

- Frontend: single-file `index.html` (~4900 líneas, JS embebido), PWA con service worker.
- Backend: Supabase (Postgres + RLS + RPC SECURITY DEFINER + Edge Functions).
- Hosting: Vercel (`https://picks3.vercel.app`).
- Auto-resultado: Edge Function `smooth-api` (Deno + Jina Reader + caché en BD).

---

## Cómo verificar el release

Ver `CHECKLIST_REGRESION_ETAPA4.md` en el repo — pasos para cubrir flujos admin + recolector + multi-banca + anti-trampa antes del tag.

---

🤖 Construido con [Claude Code](https://claude.com/claude-code) (Opus 4.7)
