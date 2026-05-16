// La Bolita Plus · Service Worker v2
const CACHE_NAME = 'bolita-v2';
const OFFLINE_URL = '/';

// Recursos que se cachean al instalar
const STATIC_ASSETS = [
  '/',
  '/index.html',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Syne:wght@400;600;700&display=swap'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      // Cachear recursos locales (los remotos pueden fallar)
      return cache.addAll([OFFLINE_URL]).catch(() => {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // No interceptar peticiones a Supabase (siempre online)
  if (url.hostname.includes('supabase.co')) {
    return;
  }

  // Para la navegación: Network-first, fallback a cache
  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
          return response;
        })
        .catch(() => caches.match(OFFLINE_URL))
    );
    return;
  }

  // Para otros recursos: Cache-first, fallback a network
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) return cached;
      return fetch(event.request).then(response => {
        if (response && response.status === 200 && response.type !== 'opaque') {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => new Response('', { status: 408 }));
    })
  );
});

// Sincronización en background (cuando vuelve la conexión)
self.addEventListener('sync', event => {
  if (event.tag === 'sync-jugadas') {
    // El cliente maneja la sincronización desde la app
    self.clients.matchAll().then(clients => {
      clients.forEach(client => client.postMessage({ type: 'SYNC_REQUEST' }));
    });
  }
});
