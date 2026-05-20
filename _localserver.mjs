// Servidor estático mínimo para probar la app en localhost.
// No requiere instalar nada: usa solo Node.js (módulos built-in).
// Arrancar con:  node _localserver.mjs
// Abrir:         http://localhost:8080
//
// El prefijo "_" del nombre es para que no se confunda con archivos del repo.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { resolve, extname, join } from 'node:path';

const PORT = 8080;
const ROOT = resolve('.');
const MIME = {
  '.html':'text/html; charset=utf-8',
  '.js':'application/javascript; charset=utf-8',
  '.mjs':'application/javascript; charset=utf-8',
  '.css':'text/css; charset=utf-8',
  '.json':'application/json; charset=utf-8',
  '.png':'image/png',
  '.jpg':'image/jpeg',
  '.svg':'image/svg+xml',
  '.ico':'image/x-icon',
  '.webmanifest':'application/manifest+json',
};

const server = createServer(async (req, res) => {
  try {
    let path = decodeURIComponent(req.url.split('?')[0]);
    if (path === '/' || path === '') path = '/index.html';
    const file = join(ROOT, path);
    // Anti-traversal: no salir del ROOT.
    if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end('Forbidden'); }
    const s = await stat(file).catch(() => null);
    if (!s || !s.isFile()) { res.writeHead(404); return res.end('Not found'); }
    const body = await readFile(file);
    const type = MIME[extname(file).toLowerCase()] || 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': type,
      // Anti-caché agresivo para que cada reload traiga la última versión.
      'Cache-Control': 'no-store, must-revalidate',
    });
    res.end(body);
  } catch (e) {
    res.writeHead(500);
    res.end('Server error: ' + e.message);
  }
});

server.listen(PORT, () => {
  console.log(`Servidor local corriendo en http://localhost:${PORT}`);
  console.log(`Sirviendo desde: ${ROOT}`);
  console.log('Ctrl+C para detener.');
});
