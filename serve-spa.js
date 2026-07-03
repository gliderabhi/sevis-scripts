#!/usr/bin/env node
/**
 * serve-spa.js — Lightweight SPA static server with API proxy
 *
 * Usage:
 *   node serve-spa.js <dist-dir> <port> <api-prefixes-csv> [exact-route-rewrites-csv]
 *
 * Example:
 *   node serve-spa.js /path/to/dist/sevis-web 4200 /user-service,/orders-service
 *   node serve-spa.js /path/to/dist/kids-study 3010 /kids-study-service /sitemap.xml=/kids-study-service/sitemap.xml
 *
 * - Serves static files from <dist-dir>
 * - Proxies any path starting with a prefix to http://localhost:8080
 * - Exact-route rewrites proxy a single path to a different gateway path
 *   (e.g. exposing a backend's /sitemap.xml at the site root)
 * - Falls back to index.html for all other paths (SPA routing)
 */

'use strict';

const http = require('http');
const fs   = require('fs');
const path = require('path');

const DIST_DIR   = path.resolve(process.argv[2] || 'dist');
const PORT       = parseInt(process.argv[3] || '4200', 10);
const PREFIXES   = (process.argv[4] || '').split(',').map(s => s.trim()).filter(Boolean);
const ROUTE_REWRITES = new Map(
  (process.argv[5] || '').split(',').map(s => s.trim()).filter(Boolean)
    .map(pair => pair.split('=').map(s => s.trim()))
);
const GATEWAY    = 'http://localhost:8080';
const BIND_HOST  = '127.0.0.1';

const MIME_TYPES = {
  '.html' : 'text/html; charset=utf-8',
  '.js'   : 'application/javascript',
  '.mjs'  : 'application/javascript',
  '.css'  : 'text/css',
  '.json' : 'application/json',
  '.png'  : 'image/png',
  '.jpg'  : 'image/jpeg',
  '.jpeg' : 'image/jpeg',
  '.gif'  : 'image/gif',
  '.svg'  : 'image/svg+xml',
  '.ico'  : 'image/x-icon',
  '.woff' : 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf'  : 'font/ttf',
  '.eot'  : 'application/vnd.ms-fontobject',
  '.mp3'  : 'audio/mpeg',
  '.mp4'  : 'video/mp4',
  '.webp' : 'image/webp',
  '.txt'  : 'text/plain',
};

// ── Proxy a request to the gateway ───────────────────────────────────────────
function proxyToGateway(req, res, targetPath) {
  const gwUrl  = new URL(GATEWAY);
  const options = {
    hostname : gwUrl.hostname,
    port     : parseInt(gwUrl.port, 10) || 8080,
    path     : targetPath || req.url,
    method   : req.method,
    headers  : Object.assign({}, req.headers, { host: gwUrl.host }),
  };

  const proxyReq = http.request(options, proxyRes => {
    res.writeHead(proxyRes.statusCode, proxyRes.headers);
    proxyRes.pipe(res, { end: true });
  });

  proxyReq.on('error', err => {
    if (!res.headersSent) res.writeHead(502).end('Bad Gateway: ' + err.message);
  });

  req.pipe(proxyReq, { end: true });
}

// ── Serve a static file ───────────────────────────────────────────────────────
function serveFile(filePath, res) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(500).end('Internal Server Error');
      return;
    }
    const ext  = path.extname(filePath).toLowerCase();
    const mime = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime });
    res.end(data);
  });
}

// ── Main request handler ──────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  const reqPath = req.url.split('?')[0];

  // 1. Exact-route rewrites (e.g. /sitemap.xml -> /kids-study-service/sitemap.xml)
  if (ROUTE_REWRITES.has(reqPath)) {
    return proxyToGateway(req, res, ROUTE_REWRITES.get(reqPath));
  }

  // 2. Proxy API prefixes to gateway
  if (PREFIXES.some(p => reqPath === p || reqPath.startsWith(p + '/'))) {
    return proxyToGateway(req, res);
  }

  // 3. Try to serve the exact static file requested
  let candidate = path.join(DIST_DIR, reqPath);

  // Prevent path traversal
  if (!candidate.startsWith(DIST_DIR)) {
    res.writeHead(403).end('Forbidden');
    return;
  }

  if (fs.existsSync(candidate)) {
    const stat = fs.statSync(candidate);
    if (stat.isFile()) {
      return serveFile(candidate, res);
    }
    // Directory — try index.html inside it
    const dirIndex = path.join(candidate, 'index.html');
    if (fs.existsSync(dirIndex)) {
      return serveFile(dirIndex, res);
    }
  }

  // 4. SPA fallback — return root index.html for Angular routing
  const indexHtml = path.join(DIST_DIR, 'index.html');
  if (fs.existsSync(indexHtml)) {
    return serveFile(indexHtml, res);
  }

  res.writeHead(404).end('Not Found');
});

server.listen(PORT, BIND_HOST, () => {
  console.log(`[serve-spa] ${path.basename(DIST_DIR)} → http://${BIND_HOST}:${PORT}`);
  if (PREFIXES.length) {
    console.log(`[serve-spa] Proxying: ${PREFIXES.join(', ')} → ${GATEWAY}`);
  }
});

process.on('SIGTERM', () => { server.close(); process.exit(0); });
process.on('SIGINT',  () => { server.close(); process.exit(0); });
