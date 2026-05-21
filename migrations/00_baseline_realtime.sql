-- =============================================================================
-- BASELINE REALTIME — snapshot 2026-05-21
-- =============================================================================
-- Configuracion de Supabase Realtime (publicacion `supabase_realtime`) y
-- REPLICA IDENTITY de las tablas suscritas.
--
-- Sin estos ADD TABLE, los cambios server-side (INSERT/UPDATE/DELETE) NO
-- se propagan a clientes suscritos via `sb.channel(...).on('postgres_changes')`,
-- aunque la suscripcion cliente este bien armada.
--
-- REPLICA IDENTITY FULL hace que eventos UPDATE/DELETE manden TODA la fila
-- (no solo la primary key). Necesario si se quiere filtrar server-side por
-- columnas distintas a la PK (ej. filter:'banquero_id=eq.UUID').
-- =============================================================================

-- =============================================================================
-- Tablas suscritas a Realtime (al snapshot)
-- =============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.jugadas;
ALTER PUBLICATION supabase_realtime ADD TABLE public.resultados;

-- REPLICA IDENTITY FULL para que UPDATE/DELETE manden la fila completa.
ALTER TABLE public.jugadas    REPLICA IDENTITY FULL;
ALTER TABLE public.resultados REPLICA IDENTITY FULL;


-- =============================================================================
-- VERIFICACION
-- =============================================================================
-- Listar tablas en supabase_realtime:
/*
SELECT schemaname, tablename FROM pg_publication_tables
 WHERE pubname = 'supabase_realtime' ORDER BY schemaname, tablename;
*/

-- Listar REPLICA IDENTITY de tablas publicas:
/*
SELECT n.nspname AS schema, c.relname AS tabla,
       CASE c.relreplident
         WHEN 'd' THEN 'default' WHEN 'f' THEN 'full'
         WHEN 'n' THEN 'nothing' WHEN 'i' THEN 'index'
       END AS replica_identity
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 ORDER BY c.relname;
*/


-- =============================================================================
-- AGREGAR MAS TABLAS EN EL FUTURO
-- =============================================================================
-- Si se quiere que otras tablas se reflejen en tiempo real (ej. ajustes,
-- limites_numeros), agregar a la publication y setear REPLICA IDENTITY:
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.<tabla>;
-- ALTER TABLE public.<tabla> REPLICA IDENTITY FULL;
--
-- Tener en cuenta: cada tabla suscrita genera trafico WebSocket. Solo
-- agregar las que el cliente realmente escucha.
