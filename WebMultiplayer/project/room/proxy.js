'use strict';
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname,'../../public');
const files = {'/ATTRIBUTION.md':['ATTRIBUTION.md','text/plain; charset=utf-8'], '/': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/style.css': ['style.css', 'text/css; charset=utf-8']};
const lanIp = process.env.YACHT_LAN_IPV4;
if (!lanIp || net.isIP(lanIp) !== 4 || lanIp === '0.0.0.0' || lanIp.startsWith('127.')) throw new Error('A LAN IPv4 address is required.');
const allowedHosts = new Set([`127.0.0.1:8765`, `localhost:8765`, `${lanIp}:8765`]);
// Only exact HTTPS origins discovered by our local tunnel launcher are trusted.
const originFile = process.env.YACHT_PUBLIC_ORIGIN_FILE;
function publicOrigin() {
  try {
    const value = fs.readFileSync(originFile, 'utf8').trim();
    const u = new URL(value);
    return u.protocol === 'https:' && u.origin === value && !u.username && !u.password ? u : null;
  } catch { return null; }
}
function requestOrigin(req) {
  if (allowedHosts.has(req.headers.host)) return `http://${req.headers.host}`;
  const u = publicOrigin();
  // cpolar connects to the loopback listener, preserving the public Host header.
  return u && req.socket.remoteAddress === '127.0.0.1' && req.headers.host === u.host ? u.origin : null;
}
const handle = (req, res) => {
  if (!requestOrigin(req)) { res.writeHead(403); res.end(); return; }
  let item = files[req.url];
  if (/^\/viewer\/[a-zA-Z0-9_.-]+$/.test(req.url)) {
    const name = req.url.slice('/viewer/'.length);
    const ext = path.extname(name);
    const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png'};
    if (types[ext]) item = ['viewer/'+name,types[ext]];
  }
  if (req.method !== 'GET' || !item) { res.writeHead(404); res.end(); return; }
  const filename = path.join(root, item[0]);
  const compressed = /\bgzip\b/.test(req.headers['accept-encoding'] || '') && fs.existsSync(filename + '.gz') && fs.statSync(filename+'.gz').mtimeMs >= fs.statSync(filename).mtimeMs;
  let etag;
  try { const stat=fs.statSync(filename+(compressed?'.gz':''));etag=`"${stat.size}-${stat.mtimeMs}-${compressed?'gz':'raw'}"`; }
  catch { res.writeHead(404);res.end();return; }
  const cacheHeaders = {'ETag':etag,'Cache-Control':'no-cache','Vary':'Accept-Encoding'};
  if(req.headers['if-none-match']===etag){res.writeHead(304,cacheHeaders);res.end();return;}
  fs.readFile(filename + (compressed ? '.gz' : ''), (err, data) => {
    if (err) { res.writeHead(500); res.end(); return; }
    res.writeHead(200, {'Content-Type': item[1], 'Content-Length':data.length, ...(compressed ? {'Content-Encoding':'gzip'} : {}), ...cacheHeaders, 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer'}); res.end(data);
  });
};
const upgrade = (req, client, head) => {
  const origin = requestOrigin(req);
  if (req.url !== '/ws' || !origin || req.headers.origin !== origin) { client.destroy(); return; }
  const upstream = net.connect(18766, '127.0.0.1');
  upstream.on('connect', () => {
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` + req.rawHeaders.reduce((s, h, i, a) => i % 2 ? s : s + h + ': ' + a[i + 1] + '\r\n', '') + '\r\n');
    if (head.length) upstream.write(head);
    client.pipe(upstream).pipe(client);
  });
  upstream.on('error', () => client.destroy()); client.on('error', () => upstream.destroy());
  client.on('close', () => upstream.destroy()); upstream.on('close', () => client.destroy());
};
for (const address of ['127.0.0.1', lanIp]) {
  const server = http.createServer(handle);
  server.on('upgrade', upgrade);
  server.on('error', err => { console.error(err.message); process.exit(1); });
  server.listen(8765, address, () => console.log(`Room page: http://${address}:8765/`));
}
