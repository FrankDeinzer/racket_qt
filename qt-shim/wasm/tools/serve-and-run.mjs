// Static COOP/COEP server + headless Chrome (DevTools protocol, Node built-ins only) for the WASM builds.
// usage: EXTRA_WAIT=<s> node serve-and-run.mjs <build-dir> <page.html> <out-dir> [timeout-s]; finishes when document.title === "BENCH-DONE".
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from "node:fs";
import { join, extname } from "node:path";
const [DIR, PAGE, OUT, TIMEOUT = "120"] = process.argv.slice(2);
mkdirSync(OUT, { recursive: true });
const MIME = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".json": "application/json", ".png": "image/png" };
const srv = createServer((req, res) => {
  let p = join(DIR, decodeURIComponent(req.url.split("?")[0])); if (!existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end("nf"); }
  res.writeHead(200, { "Content-Type": MIME[extname(p)] || "application/octet-stream", "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-store" });
  res.end(readFileSync(p));
}).listen(8123, "127.0.0.1");
const PORT = 9334, CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--remote-debugging-address=127.0.0.1", `--user-data-dir=${OUT}/profile`, "--no-first-run", "--window-size=1100,900", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms)); const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
try {
  let ok = false; for (let i = 0; i < 50 && !ok; i++) { try { await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json(); ok = true; } catch { await sleep(200); } }
  if (!ok) throw new Error("DevTools nicht erreichbar");
  const t = await (await fetch(`http://127.0.0.1:${PORT}/json/new?${encodeURIComponent("about:blank")}`, { method: "PUT" })).json();
  const ws = new WebSocket(t.webSocketDebuggerUrl); await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const pend = new Map(); const cons = [];
  ws.onmessage = (m) => { const d = JSON.parse(m.data);
    if (d.id && pend.has(d.id)) { pend.get(d.id)(d); pend.delete(d.id); }
    else if (d.method === "Runtime.consoleAPICalled") cons.push(d.params.type + ": " + d.params.args.map((a) => a.value ?? a.description).join(" "));
    else if (d.method === "Runtime.exceptionThrown") cons.push("EXC: " + (d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text)); };
  const send = (method, params = {}) => new Promise((res) => { const i = ++id; pend.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
  const ev = async (e) => (await send("Runtime.evaluate", { expression: e, returnByValue: true })).result?.result?.value;
  await send("Runtime.enable"); await send("Page.enable");
  await send("Page.navigate", { url: `http://127.0.0.1:8123/${PAGE}` }); log("navigiert");
  await sleep(2000); log("isolated:", await ev("self.crossOriginIsolated"));
  const t0 = Date.now(); let done = false;
  while (Date.now() - t0 < Number(TIMEOUT) * 1000) { await sleep(1500); if ((await ev("document.title")) === "BENCH-DONE") { done = true; break; } }
  await sleep(Number(process.env.EXTRA_WAIT || 0) * 1000);
  log(done ? "fertig" : "TIMEOUT", ((Date.now() - t0) / 1000).toFixed(1) + " s");
  writeFileSync(`${OUT}/bench.json`, JSON.stringify(await ev("JSON.stringify(window.__bench||null)")) );
  writeFileSync(`${OUT}/console.txt`, cons.join("\n"));
  const shot = await send("Page.captureScreenshot", { format: "png" }); writeFileSync(`${OUT}/screenshot.png`, Buffer.from(shot.result.data, "base64"));
  console.log(await ev("JSON.stringify(window.__bench||null)")); ws.close();
} catch (e) { console.error("FEHLER:", e.message); process.exitCode = 1; }
finally { chrome.kill("SIGTERM"); srv.close(); await sleep(500); if (chrome.exitCode === null) chrome.kill("SIGKILL"); log("beendet"); setTimeout(() => process.exit(), 200); }
