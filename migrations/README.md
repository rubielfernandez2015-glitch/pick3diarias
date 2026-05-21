# Migraciones SQL

Snapshot del schema de Supabase (`public` + `banca`) versionado en el repo. Permite recrear la BD desde cero corriendo los scripts en orden, y deja un registro auditable de cómo evolucionó el esquema.

## Estructura

```
migrations/
├── README.md                           ← este archivo
├── 00_baseline_functions.sql           ← todas las funciones (RPCs + triggers + helpers)
├── 00_baseline_policies.sql            ← RLS policies de las tablas críticas
├── 00_baseline_grants.sql              ← privilegios de roles (anon/authenticated)
├── 00_baseline_realtime.sql            ← tablas suscritas a Realtime
└── NNN_<descripcion>.sql               ← migraciones futuras numeradas
```

**Snapshot tomado:** 2026-05-21 (release `v1.0.0` + post-release hardening).

## Qué NO incluye este snapshot

Estructura de tablas (CREATE TABLE …) y triggers DDL **no** están versionados acá. Razón: las tablas se crearon hace meses en el dashboard de Supabase y no tuvieron cambios desde entonces; el dump completo requiere `pg_dump` o `supabase db dump` (CLI Supabase, fuera del alcance de este snapshot manual).

Si en el futuro necesitás un snapshot full (incluyendo tablas), corré desde tu máquina con el CLI Supabase configurado:

```bash
supabase db dump --schema public,banca,auth -f migrations/00_baseline_full.sql
```

Y comiteás ese archivo. Por ahora alcanza con lo que hay: las RPCs son lo que escribimos a mano, las policies son lo que protege la app, los grants reflejan los `REVOKE` aplicados.

## Cómo agregar una migración nueva

1. Crear archivo `migrations/NNN_descripcion_corta.sql` con el SQL del cambio.
2. Ejecutar en SQL Editor de Supabase.
3. Hacer commit con el archivo nuevo y un mensaje claro de qué cambió.

Ejemplo:
```
migrations/001_add_recolector_telefono.sql
```

```sql
-- Agrega columna telefono opcional a banca.recolectores para notificaciones SMS.
ALTER TABLE banca.recolectores
  ADD COLUMN IF NOT EXISTS telefono text;
```

## Cómo recrear todo desde cero (otra cuenta Supabase / disaster recovery)

1. Crear el proyecto Supabase nuevo.
2. Crear tablas a mano desde el dashboard (o usar el dump full si lo tenés).
3. Correr en orden:
   ```
   00_baseline_functions.sql
   00_baseline_policies.sql
   00_baseline_grants.sql
   00_baseline_realtime.sql
   ```
4. Después correr cada `NNN_*.sql` en orden numérico.
5. Actualizar `index.html` con los URLs/keys nuevos (líneas con `soshfmpdymryihimcwik` y `publishable key`).

## Estado de RPCs principales (resumen)

| Schema  | Función                          | Para qué                                                |
|---------|----------------------------------|---------------------------------------------------------|
| `banca` | `login_recolector`               | Login recolector con código de banca (overload 2 y 3 args) |
| `banca` | `_rec_por_token`                 | Helper interno: valida token → devuelve fila de sesión   |
| `banca` | `_gen_codigo_banca`              | Helper interno: genera código corto único de banca       |
| `banca` | `cerrar_sesion`                  | Cierre día/noche calculado server-side (Punto 4 F2)      |
| `banca` | `cerrar_sesion_preview`          | A/B testing read-only del cálculo de cierre              |
| `banca` | `recolector_jugadas_fecha`       | Lectura de jugadas del día por recolector via token      |
| `banca` | `recolector_jugadas_pendientes`  | Jugadas pendientes del recolector                        |
| `banca` | `recolector_insertar_jugadas`    | Insertar jugadas con validación de token                 |
| `banca` | `recolector_resultados`          | Etapa 2: leer resultados via token (sin SELECT anon)     |
| `banca` | `recolector_clientes`            | Etapa 2: autocompletar nombres via token                 |
| `banca` | `acumulados_recolector`          | Acumulados manuales del recolector via token             |
| `banca` | `cambiar_password_recolector`    | Self-service cambio de clave via token                   |
| `banca` | `movimientos_recolector`         | Wallet entregas/recargas del recolector                  |
| `public`| `audit_log`                      | Inserta auditoría con identidad server-derivada          |
| `public`| `historial_recolector`           | Historial agregado de cierres por recolector             |
