#!/usr/bin/env node
// Static server for the WASM builds: sends the headers the Qt+Racket module needs (SharedArrayBuffer => cross-origin isolation).
// usage: node serve.mjs <dir> [port=8123]      then open  http://localhost:<port>/<page>   (localhost counts as a secure context)
import { createServer } from "node:http";
import { readFileSync, existsSync, statSync } from "node:fs";
import { join, extname, resolve, normalize } from "node:path";
const [DIR0, PORT = "8123"] = process.argv.slice(2);
if (!DIR0) { console.error("usage: node serve.mjs <dir> [port]"); process.exit(2); }
const DIR = resolve(DIR0);
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".wasm": "application/wasm", ".json": "application/json", ".png": "image/png", ".data": "application/octet-stream" };
createServer((req, res) => {
  const rel = normalize(decodeURIComponent(req.url.split("?")[0])).replace(/^(\.\.[\/\\])+/, "");
  const p = join(DIR, rel === "/" ? "/exam-host.html" : rel);
  if (!p.startsWith(DIR) || !existsSync(p) || statSync(p).isDirectory()) {
    console.log("404", req.url); res.writeHead(404, { "Content-Type": "text/plain" }); return res.end("nicht gefunden: " + req.url);
  }
  res.writeHead(200, { "Content-Type": MIME[extname(p)] || "application/octet-stream",
    "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cross-Origin-Resource-Policy": "same-origin", "Cache-Control": "no-store" });
  res.end(readFileSync(p));
}).listen(Number(PORT), "127.0.0.1", () => {
  console.log(`serving ${DIR}\n  Pruefungsseite : http://localhost:${PORT}/exam-host.html\n  nur DrRacket   : http://localhost:${PORT}/racketqt_wasm.html\n  (Strg+C beendet)`);
});
