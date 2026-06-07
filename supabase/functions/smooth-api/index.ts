// Supabase Edge Function: smooth-api
// Resultado Florida Pick 3 (Midday/Evening) vía Jina Reader, CON CACHÉ EN BASE.
// - Si ya se tiene el resultado de HOY para esa sesión -> lo devuelve de la base (instantáneo, sin Jina).
// - Anti-martilleo: si se consultó hace < 90s, devuelve lo cacheado (no re-pega a Jina).
// - Si Jina falla pero hay algo cacheado, devuelve lo cacheado (resiliente).
// Jina se llama ~1 vez por sesión/día -> nunca lo throttlea (no más 451/429).
// Tabla requerida: public.resultado_cache (ver SQL aparte).
// Desplegar PÚBLICA (Verify JWT OFF). Nombre EXACTO: smooth-api.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const DESTINO: Record<string, string> = {
  dia:   "https://www.lotteryusa.com/florida/midday-pick-3/",
  noche: "https://www.lotteryusa.com/florida/pick-3/",
};

const BUILD = "2026-06-07-iso-mes-abreviado"; // marca de versión: aparece en cada respuesta JSON para confirmar qué código está desplegado
const JINA_KEY = "jina_e4e6345c8c46419e873c4dc77d4ef3fagT6Bnc1Vc6Gq9PxMTPHVqSS2D2Pt";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function hoyET(): string {
  // ISO "2026-06-07" en hora del Este. en-CA da formato ISO; comparar en ISO
  // evita depender del idioma/abreviatura del runtime o de la fuente.
  return new Date().toLocaleDateString("en-CA", { timeZone: "America/New_York" });
}

function toISO(s: string): string {
  // "May 18, 2026" o "Jun 6, 2026" (mes completo O abreviado) -> "2026-05-18"
  // (vacío si no parsea). Parseo MANUAL a propósito: new Date("May 18, 2026")
  // depende de la TZ/locale del runtime (en el edge de Supabase corría el día
  // +1). Esto es determinista. Match por las 3 primeras letras del mes para
  // tolerar "June"/"Jun"/"Sept" — lotteryusa pasó a abreviar el mes.
  if (!s) return "";
  const M: Record<string, string> = {
    jan: "01", feb: "02", mar: "03", apr: "04",
    may: "05", jun: "06", jul: "07", aug: "08",
    sep: "09", oct: "10", nov: "11", dec: "12",
  };
  const m = s.match(/([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})/);
  if (!m) return "";
  const mm = M[m[1].toLowerCase().slice(0, 3)];
  if (!mm) return "";
  return `${m[3]}-${mm}-${m[2].padStart(2, "0")}`;
}

function parse(txt: string): { numero: string; fecha: string } | null {
  // SOLO filas de la TABLA de resultados:
  //   "| Monday, May 18, 2026 | * 4 * 0 * 6 * FB:0 | Top prize $500 |"
  //   "| Saturday, Jun 6, 2026 | * 7 * 1 * 0 * FB:4 | Top prize $500 |"
  // El \| inicial y el \| antes de los dígitos impiden capturar la cabecera
  // "Next draw / Tomorrow, May 19, 2026" (no está en formato de tabla) — ese
  // era el bug: pegaba el número de hoy con la fecha de mañana.
  const m = txt.match(
    /\|\s*(?:[A-Za-z]+,\s*)?([A-Za-z]+\s+\d{1,2},\s*\d{4})\s*\|\s*\*\s*(\d)\s*\*\s*(\d)\s*\*\s*(\d)\s*\*\s*FB/i,
  );
  if (!m) return null;
  const fecha = toISO(m[1].trim()); // ISO "2026-06-06" ("" si no se reconoce el mes)
  return { numero: m[2] + m[3] + m[4], fecha };
}

async function cacheGet(sesion: string) {
  try {
    const r = await fetch(
      `${SB_URL}/rest/v1/resultado_cache?sesion=eq.${sesion}&select=*`,
      { headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}` } },
    );
    if (!r.ok) return null;
    const a = await r.json();
    return Array.isArray(a) && a.length ? a[0] : null;
  } catch { return null; }
}

async function cacheSet(sesion: string, fecha: string, numero: string) {
  try {
    await fetch(`${SB_URL}/rest/v1/resultado_cache`, {
      method: "POST",
      headers: {
        apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates",
      },
      body: JSON.stringify({ sesion, fecha, numero, ts: new Date().toISOString() }),
    });
  } catch { /* cache best-effort */ }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);
  const sesion = (url.searchParams.get("sesion") || "dia").toLowerCase() === "noche" ? "noche" : "dia";
  const json = (o: Record<string, unknown>, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify({ ...o, build: BUILD }), {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json", ...extra },
    });

  const hoy = hoyET(); // ISO "2026-06-07"
  const cached = await cacheGet(sesion);
  // El caché puede tener filas viejas con fecha en texto ("Jun 6, 2026"); las
  // normalizamos a ISO para comparar y para responder de forma consistente.
  const cachedISO = cached ? (/^\d{4}-\d{2}-\d{2}$/.test(cached.fecha) ? cached.fecha : toISO(cached.fecha)) : "";

  // 1) Ya tenemos el resultado de HOY -> instantáneo, sin Jina
  if (cached && cachedISO === hoy && /^\d{3}$/.test(cached.numero)) {
    return json({ ok: true, numero: cached.numero, fecha: cachedISO, sesion, fuente: "cache" });
  }
  // 2) Anti-martilleo: consultado hace < 90s -> devuelve lo cacheado
  if (cached && cached.ts && (Date.now() - new Date(cached.ts).getTime() < 90000) && /^\d{3}$/.test(cached.numero)) {
    return json({ ok: true, numero: cached.numero, fecha: cachedISO, sesion, fuente: "cache-reciente" });
  }

  // 3) Pedir a Jina
  try {
    const r = await fetch("https://r.jina.ai/" + DESTINO[sesion], {
      headers: {
        Accept: "text/plain",
        "X-Return-Format": "markdown",
        "User-Agent": "Mozilla/5.0 (compatible; LaBolitaBot/1.0)",
        Authorization: `Bearer ${JINA_KEY}`,
      },
      signal: AbortSignal.timeout(18000),
    });
    if (!r.ok) {
      if (cached && /^\d{3}$/.test(cached.numero)) {
        return json({ ok: true, numero: cached.numero, fecha: cachedISO, sesion, fuente: "cache-fallback" });
      }
      return json({ ok: false, error: "proxy HTTP " + r.status, sesion });
    }
    const p = parse(await r.text());
    if (p && /^\d{3}$/.test(p.numero)) {
      await cacheSet(sesion, p.fecha, p.numero); // p.fecha ya es ISO
      return json({ ok: true, numero: p.numero, fecha: p.fecha, sesion, fuente: "jina" }, { "Cache-Control": "no-store" });
    }
    if (cached && /^\d{3}$/.test(cached.numero)) {
      return json({ ok: true, numero: cached.numero, fecha: cachedISO, sesion, fuente: "cache-fallback" });
    }
    return json({ ok: false, error: "no se pudo parsear", sesion });
  } catch (e) {
    if (cached && /^\d{3}$/.test(cached.numero)) {
      return json({ ok: true, numero: cached.numero, fecha: cachedISO, sesion, fuente: "cache-fallback" });
    }
    return json({ ok: false, error: String((e as Error)?.message || e), sesion });
  }
});
