// Local server for the browser measurement. No dependencies.
//
// Usage (from the repository root, after build.rb):
//   node bench/browser/serve.mjs <label> <runs> <n> [<n> ...] [--split]
// then open http://127.0.0.1:8765/page.html?browser=<label> in the browser
// (run.zsh does this for Chrome and Safari).
//
// The plan is every n, <runs> times each. The index is served from the
// pre-compressed index-<n>.json.gz with Content-Encoding: gzip, so the
// browser downloads the gzip size and decodes it as a real site would.
// With --split the page loads the split index (split-<n>/) instead; its
// files are served the same way, from split-<n>-gz/. Each index response
// carries X-Gzip-Bytes, the size sent, so the page can count what it fetched.
// Results go to results/<label>.json; the server exits when the plan is done.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const split = args.includes('--split');
const [label, runs, ...ns] = args.filter((a) => a !== '--split');
if (!label || !runs || ns.length === 0) {
  console.error('usage: serve.mjs <label> <runs> <n> [<n> ...]');
  process.exit(2);
}
const plan = ns.flatMap((n) => Array.from({ length: Number(runs) }, (_, i) => ({ n: Number(n), run: i + 1, split })));
let next = 0;
const results = [];
const PORT = 8765;

const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8' };
const send = (res, status, body, headers = {}) => {
  res.writeHead(status, { 'Cache-Control': 'no-store', ...headers });
  res.end(body);
};

http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname === '/next') {
    return send(res, 200, JSON.stringify(next < plan.length ? plan[next] : { done: true }), { 'Content-Type': types['.json'] });
  }
  if (req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      send(res, 204, '');
      if (url.pathname === '/error') { console.error('page error:', body); process.exit(1); }
      const r = JSON.parse(body);
      results.push(r);
      next += 1;
      console.log(`${label} n=${r.n} run=${r.run} load=${r.load_ms.toFixed(0)}ms mismatch=${r.mismatch.length}`);
      if (next === plan.length) {
        const out = path.join(HERE, 'results', `${label}.json`);
        fs.mkdirSync(path.dirname(out), { recursive: true });
        fs.writeFileSync(out, JSON.stringify(results, null, 1) + '\n');
        console.log(`wrote ${out}`);
        setTimeout(() => process.exit(0), 500);
      }
    });
    return;
  }
  const m = url.pathname.match(/^\/index-(\d+)\.json$/);
  if (m) {
    const body = fs.readFileSync(path.join(HERE, 'cache', `index-${m[1]}.json.gz`));
    return send(res, 200, body, { 'Content-Type': types['.json'], 'Content-Encoding': 'gzip', 'X-Gzip-Bytes': body.length });
  }
  const s = url.pathname.match(/^\/split-(\d+)\/(index|[0-9a-f]{16}|latin-[0-9a-f]{16})\.json$/);
  if (s) {
    const file = path.join(HERE, 'cache', `split-${s[1]}-gz`, `${s[2]}.json`);
    if (!fs.existsSync(file)) return send(res, 404, 'not found');
    const body = fs.readFileSync(file);
    return send(res, 200, body, { 'Content-Type': types['.json'], 'Content-Encoding': 'gzip', 'X-Gzip-Bytes': body.length });
  }
  const file = path.join(HERE, path.normalize(url.pathname).replace(/^(\.\.[/\\])+/, ''));
  if (!file.startsWith(HERE) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return send(res, 404, 'not found');
  send(res, 200, fs.readFileSync(file), { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
}).listen(PORT, '127.0.0.1', () => console.log(`${label}: ${plan.length} steps, http://127.0.0.1:${PORT}/page.html?browser=${label}`));
