// =============================================================================
// Edge Function: recognize-jugada
// =============================================================================
// Proxy seguro entre el PWA y Google Gemini para leer fotos de jugadas.
// - Esconde la API key de Gemini (nunca llega al navegador).
// - Valida que el llamador sea un recolector real (token) o un banquero
//   autenticado (JWT de Supabase), para que nadie ajeno gaste el saldo.
// - Devuelve el texto transcrito en formato NN-monto (uno por renglon).
//
// SECRETOS A CONFIGURAR (Supabase → Project Settings → Edge Functions → Secrets):
//   GEMINI_API_KEY   (obligatorio)  una o VARIAS keys de Google AI Studio
//                                   separadas por coma: "key1,key2,key3".
//                                   Si una se queda sin cupo, prueba la siguiente.
//   GEMINI_MODEL     (opcional)     por defecto gemini-2.5-flash
//   RESUMEN_TOOL_KEY (opcional)     codigo de acceso para la herramienta de
//                                   resumen (resumen.html), que no usa login.
// (SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los inyecta Supabase solo.)
//
// DESPLIEGUE: ver supabase/functions/README_DESPLIEGUE.md
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PROMPT = `Eres un lector experto de boletas de la bolita (loteria) escritas a mano, a lapiz, en espanol cubano.
Te paso la FOTO de una boleta. Transcribe SOLO las jugadas, una por renglon, en este formato EXACTO:

NN-MONTO

Donde:
- NN = el numero jugado, de 0 a 99 (dos digitos, ej. 05, 37, 98).
- MONTO = la cantidad apostada (decimales con punto, ej. 10, 5.5, 12.50).
- SIEMPRE separa con un guion. NUNCA dejes un espacio como separador.
- Un solo renglon por jugada. Sin texto extra, sin encabezados, sin explicaciones.

Casos a tener en cuenta:
- El separador entre un numero y su monto puede ser guion, raya, coma, "de", "con", "x" o un espacio: tu SIEMPRE devuelve NN-MONTO con guion.

- COMO DECIDIR cuando hay VARIOS numeros o DOS COLUMNAS de numeros (regla clave, aplicala SIEMPRE):
  1) SI HAY una FLECHA, llave, corchete, linea o un monto escrito UNA sola vez que aplica a TODO el grupo:
     entonces TODOS los numeros (de TODAS las columnas) son jugadas DISTINTAS y CADA UNO lleva ESE mismo monto.
     Devuelve un renglon por numero: numero-montoCompartido. (NO emparejes columna1 con columna2.)
  2) SI NO HAY flecha ni un monto general:
     entonces es una tabla de PARES: la columna IZQUIERDA es el numero y la DERECHA es su monto.
     Empareja por fila: numeroIzquierda-montoDerecha.
  La presencia de la flecha / monto-unico es lo que DECIDE: con flecha = monto compartido para todos;
  sin flecha = pares numero|monto.

- Si una cifra esta borrosa o dudosa, ponla igual pero agrega " ?" al final de ese renglon.
- No inventes jugadas que no veas. Si no hay jugadas legibles, responde solo: (sin jugadas)`;

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Valida al llamador. Devuelve true si es recolector con token vigente,
// banquero con JWT valido, o la herramienta de resumen con su codigo de acceso
// (RESUMEN_TOOL_KEY). Asi nadie ajeno puede consumir la API de Gemini.
async function autorizado(req: Request, token: string | null, toolKey: string | null): Promise<boolean> {
  // Herramienta de resumen (sin login): codigo de acceso compartido.
  const expectedTool = Deno.env.get("RESUMEN_TOOL_KEY");
  if (expectedTool && toolKey && toolKey === expectedTool) return true;
  if (token) {
    const { data } = await supabaseAdmin
      .schema("banca")
      .from("recolector_sesiones")
      .select("token")
      .eq("token", token)
      .limit(1)
      .maybeSingle();
    if (data) return true;
  }
  const auth = req.headers.get("Authorization");
  if (auth?.startsWith("Bearer ")) {
    const { data, error } = await supabaseAdmin.auth.getUser(auth.slice(7));
    if (!error && data?.user) return true;
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "metodo no permitido" }), {
      status: 405, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  try {
    const { image_b64, mime, token, tool } = await req.json();
    if (!image_b64) {
      return new Response(JSON.stringify({ error: "falta image_b64" }), {
        status: 400, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    if (!(await autorizado(req, token ?? null, tool ?? null))) {
      return new Response(JSON.stringify({ error: "no autorizado" }), {
        status: 401, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    // GEMINI_API_KEY puede tener VARIAS keys separadas por coma. Cada key gratis
    // tiene su propio cupo diario (si son de proyectos distintos), asi que si
    // una se queda sin cupo (429), probamos la siguiente automaticamente.
    const keys = (Deno.env.get("GEMINI_API_KEY") || "").split(",").map((k) => k.trim()).filter(Boolean);
    if (keys.length === 0) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY no configurada" }), {
        status: 500, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    const model = Deno.env.get("GEMINI_MODEL") || "gemini-2.5-flash";

    const reqBody = JSON.stringify({
      contents: [{
        parts: [
          { text: PROMPT },
          { inline_data: { mime_type: mime || "image/jpeg", data: image_b64 } },
        ],
      }],
      generationConfig: { temperature: 0 },
    });

    let lastErr = "sin respuesta";
    for (const key of keys) {
      const gRes = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: reqBody },
      );
      const gJson = await gRes.json();
      if (gRes.ok) {
        const text = gJson.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text).join("") || "";
        return new Response(JSON.stringify({ text }), {
          headers: { ...CORS, "Content-Type": "application/json" },
        });
      }
      // Esta key fallo (cupo agotado u otro error): guardamos el motivo y probamos la siguiente.
      lastErr = gJson.error?.message || String(gRes.status);
    }
    // Todas las keys fallaron.
    return new Response(JSON.stringify({ error: "gemini: " + lastErr }), {
      status: 502, headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
