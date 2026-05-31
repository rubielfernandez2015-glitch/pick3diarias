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

const PROMPT = `Eres un experto leyendo apuestas de la bolita (loteria) cubana en fotos, hojas manuscritas y mensajes de WhatsApp.

OBJETIVO: extraer TODOS los numeros jugados (de 00 a 99) con su monto y devolver UNA linea por cada par numero-monto, en este formato EXACTO:

NN-MONTO

(NN = numero de dos digitos 00-99; MONTO = cantidad, con punto si tiene decimales; SIEMPRE con un guion; una linea por par; sin texto extra ni encabezados.)

REGLAS GENERALES (muy importantes):
- IGNORA los NOMBRES de personas/clientes (ej. Pedro, Tomas, Bordo, Mar, Alana). No son jugadas.
- IGNORA encabezados/referencias de FECHA (ej. "30/5", "31-Dic", "dia 30", "Noche", "Tarde"). PERO un numero que tiene su monto o aportes (ej. "30-240" o "30 = 30-15") SI es una jugada: incluelo. Solo ignora un numero si esta suelto como fecha, sin monto.
- IGNORA los TOTALES (la suma de todo, normalmente DEBAJO o al final de las jugadas, a veces con "TOTAL" o en recuadro). OJO: un numero en CIRCULO o junto a una raya NO es total: es el MONTO de esa jugada o grupo.
- NUNCA sumes tu los montos. Si un numero recibe varios montos, emite VARIAS lineas con el mismo numero; el sistema suma. Asi no hay errores de cuenta.
- Lee el monto COMPLETO con todos sus digitos: un 10 no es 1, un 100 no es 10.
- Expande SIEMPRE grupos, terminales y rangos a numeros individuales 00-99.

FORMATOS (expande todo a lineas NN-MONTO):
1) NUMERO-MONTO directo: "49-30" -> 49-30 ; "50-1350" -> 50-1350. El monto puede venir como numero pequeno al lado/arriba ("14 |50" -> 14-50) o entre parentesis o circulo ("20=(100)" o "20 (100)" -> 20-100).
2) HOJA POR FILAS / pre-numerada: el numero esta al INICIO de la fila (puede venir IMPRESO o a maquina) y los montos escritos en ESA fila pertenecen a ESE numero, AUNQUE NO haya "=" ni guion entre el numero y los montos. Ej: fila "4" con "50-550-200" -> 04-50, 04-550, 04-200 (todos son del 04; si hay varios montos, una linea por cada uno). Filas SIN monto = sin jugada (ignorar). El "4" es el numero 04; el "100" del final de la hoja es el 00.
3) GRUPO CON MONTO COMUN (raya/flecha): una RAYA o FLECHA (vertical o larga) que corre junto a una LISTA de numeros los AGRUPA; el monto escrito JUNTO a esa raya (arriba, al lado o en circulo) aplica a TODOS los numeros del grupo. En una columna puede haber VARIOS grupos divididos por rayas, cada uno con su monto. Tambien sirve "de 50" o un monto escrito una sola vez para el grupo. Repite cada numero del grupo con su monto.
   - Asteriscos (WhatsApp): "44*22*66*77*99 de 50" -> 44-50,22-50,66-50,77-50,99-50.
   - Digitos pegados en pares: "10203040 de 100" -> 10-100,20-100,30-100,40-100.
4) RANGO: con la palabra "al", o con guion cuando hay "= monto". "01 al 10 = 40" -> 01-40,02-40,...,10-40 ; "20-29 = 50" -> 20-50,21-50,...,29-50. (El guion es RANGO solo si los dos lados son numeros y hay "= monto" o "al"; un "numero-monto" suelto NO es rango.)
5) TERMINAL ("afuera"/"terminal") SOLO cuando lo dice explicito: un numero NUNCA se expande a terminal por si solo; en una hoja que lista numeros (01..99) cada uno es ESE numero individual con su(s) monto(s). Expande a terminal solo si dice "afuera" o "terminal", o es un rango de terminales ("10-00"). "0 afuera de 150" -> 00-150,10-150,...,90-150 ; "terminal 2 de 100" -> 02-100,12-100,...,92-100.
6) UN NUMERO CON VARIOS APORTES: "01 = 35-10-20-25-200" -> 01-35,01-10,01-20,01-25,01-200 (una linea por aporte; el sistema suma). Si una terminal recibe varios montos ("terminal 2 -> 100 750"), por cada numero de la terminal emite una linea por cada monto (02-100, 02-750, 12-100, 12-750, ... , 92-100, 92-750).

DUDAS:
- Si una cifra esta borrosa o dudosa, ponla igual y agrega " ?" al final del renglon.
- No inventes numeros que no veas. Si no hay jugadas legibles, responde solo: (sin jugadas)`;

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
    const { image_b64, mime, token, tool, b } = await req.json();
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
        // Metrica de uso de la herramienta de resumen (no falla la respuesta si esto falla).
        if (b) { try { await supabaseAdmin.rpc("log_uso_resumen", { p_codigo: String(b) }); } catch (_) { /* ignorar */ } }
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
