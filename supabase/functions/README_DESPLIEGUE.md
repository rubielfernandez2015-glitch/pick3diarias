# Desplegar la Edge Function `recognize-jugada`

Proxy seguro para leer fotos de jugadas con Gemini sin exponer la API key.

## Opción A — Dashboard de Supabase (más simple, sin instalar nada)

1. Entra a tu proyecto en https://supabase.com/dashboard → **Edge Functions**.
2. **Create a new function** → nombre exacto: `recognize-jugada`.
3. Pega el contenido de `recognize-jugada/index.ts` en el editor → **Deploy**.
4. Ve a **Project Settings → Edge Functions → Secrets** (o **Manage secrets**) y agrega:
   - `GEMINI_API_KEY` = tu key gratis de Google AI Studio.
   - (opcional) `GEMINI_MODEL` = `gemini-2.5-flash` (o el que te dio mejor resultado).
5. Listo. La URL queda como:
   `https://<TU-PROYECTO>.supabase.co/functions/v1/recognize-jugada`

## Opción B — CLI (si ya usas la CLI de Supabase)

```bash
supabase functions deploy recognize-jugada
supabase secrets set GEMINI_API_KEY=tu_key_aqui
supabase secrets set GEMINI_MODEL=gemini-2.5-flash   # opcional
```

## Probar que funciona (sin la app todavía)

Puedes apuntar la página de laboratorio (`lab/ocr-test.html`) a la función en vez de a
Gemini directo, o probar con curl (necesitas un token de recolector válido o el JWT):

```bash
curl -X POST "https://<TU-PROYECTO>.supabase.co/functions/v1/recognize-jugada" \
  -H "Content-Type: application/json" \
  -d '{"image_b64":"<base64-de-una-foto>","mime":"image/jpeg","token":"<token-recolector>"}'
```

Respuesta esperada: `{"text":"05-10\n37-5.5\n..."}`

## Notas
- `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase automáticamente; NO los pongas como secreto.
- La función valida al llamador (token de recolector vigente o JWT de banquero) para
  que nadie ajeno gaste tu saldo de Gemini.
- El prompt vive en el servidor (en `index.ts`); si querés afinarlo, editás ahí y re-desplegás.
