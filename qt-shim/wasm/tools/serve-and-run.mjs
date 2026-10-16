// Static COOP/COEP server + headless Chrome (DevTools protocol, Node built-ins only) for the WASM builds.
// CHROME_GPU=1: no SwiftShader flags (real GPU via ANGLE/Metal); logs UNMASKED_RENDERER so the result says which renderer ran.
// usage: EXTRA_WAIT=<s> node serve-and-run.mjs <build-dir> <page.html> <out-dir> [timeout-s]; finishes when document.title === "BENCH-DONE".
import { spawn, execSync } from "node:child_process";
import { createServer } from "node:http";
import { readFileSync, writeFileSync, mkdirSync, existsSync, statSync } from "node:fs";
import { join, extname } from "node:path";
const [DIR, PAGE, OUT, TIMEOUT = "120"] = process.argv.slice(2);
const HTTP_PORT = Number(process.env.HTTP_PORT || 8123);   // HTTP_PORT=8124 to run next to a server on 8123
mkdirSync(OUT, { recursive: true });
const MIME = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".json": "application/json", ".png": "image/png", ".css": "text/css", ".svg": "image/svg+xml", ".gif": "image/gif", ".woff": "font/woff", ".woff2": "font/woff2", ".txt": "text/plain" };
const srv = createServer((req, res) => {
  let p = join(DIR, decodeURIComponent(req.url.split("?")[0])); if (!existsSync(p) || statSync(p).isDirectory()) { res.writeHead(404); return res.end("nf"); }
  res.writeHead(200, { "Content-Type": MIME[extname(p)] || "application/octet-stream", "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-store" });
  res.end(readFileSync(p));
}).listen(HTTP_PORT, "127.0.0.1");
const PORT = 9334, CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--remote-debugging-address=127.0.0.1", `--user-data-dir=${OUT}/profile`, "--no-first-run", "--window-size=1100,900", ...(process.env.CHROME_GPU ? ["--enable-gpu", "--ignore-gpu-blocklist"] : ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]), "about:blank"], { stdio: "ignore", detached: true });

// Chrome runs in its own process group (detached) so that it and ALL its helper processes can be killed together, whatever way node ends
// (normal exit, error, SIGTERM from `timeout`, Ctrl+C).  Without this an aborted run left a headless Chrome with a busy WASM renderer behind.
let chromeKilled = false;
const killChrome = () => { if (chromeKilled) return; chromeKilled = true; try { process.kill(-chrome.pid, "SIGKILL"); } catch { try { chrome.kill("SIGKILL"); } catch {} } };
process.on("exit", killChrome);
for (const sig of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(sig, () => { killChrome(); process.exit(130); });
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
  // clipboard round trips (CLIPBOARD=1): grant read/write so navigator.clipboard works in headless Chrome
  if (process.env.CLIPBOARD) await send("Browser.grantPermissions", { origin: `http://127.0.0.1:${HTTP_PORT}`, permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"] });
  await send("Page.navigate", { url: `http://127.0.0.1:${HTTP_PORT}/${PAGE}` }); log("navigiert");
  await sleep(2000); log("isolated:", await ev("self.crossOriginIsolated"));
  log("renderer:", await ev(`(()=>{const c=document.createElement("canvas").getContext("webgl2");if(!c)return "kein WebGL2";const e=c.getExtension("WEBGL_debug_renderer_info");return e?c.getParameter(e.UNMASKED_RENDERER_WEBGL):"?"})()`));
  const t0 = Date.now(); let done = false;
  while (Date.now() - t0 < Number(TIMEOUT) * 1000) { await sleep(1500); if ((await ev("document.title")) === "BENCH-DONE") { done = true; break; } }
  // A real user moves the mouse over many points; one jumping mouseMoved gives Qt-WASM no Enter/Leave for the new widget
  // (switchable-button% needs `entering?` before it accepts a click) -- so glide from the last position in small steps.
  let lastX = 5, lastY = 5;
  const glideClick = async (x, y) => {
    const steps = 14;
    for (let i = 1; i <= steps; i++)
      await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: lastX + (x - lastX) * i / steps, y: lastY + (y - lastY) * i / steps, buttons: 0 });
    await sleep(120);
    for (const type of ["mousePressed", "mouseReleased"])
      await send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1, buttons: type === "mousePressed" ? 1 : 0 });
    lastX = x; lastY = y;
  };
  // CLICK_AT="x,y[;x,y...]" (CSS px) sends real mouse clicks after CLICK_AFTER seconds (default 20), then EXTRA_WAIT runs on.
  if (process.env.CLICK_AT) {
    await sleep(Number(process.env.CLICK_AFTER || 20) * 1000);
    for (const pt of process.env.CLICK_AT.split(";")) {
      const [x, y] = pt.split(",").map(Number);
      await glideClick(x, y);
      log("klick", x, y);
      await sleep(1500);
    }
  }
  // KEYS="text" sends real key events (printable chars, "\n" = Enter, "\b" = Backspace) after KEYS_AFTER seconds (default 0), KEY_GAP ms apart (default 150).
  if (process.env.KEYS) {
    await sleep(Number(process.env.KEYS_AFTER || 0) * 1000);
    const named = { "\n": ["Enter", 13], "\b": ["Backspace", 8] };
    for (const ch of process.env.KEYS) {
      const [key, code] = named[ch] ?? [ch, ch.toUpperCase().charCodeAt(0)];
      const base = { key, code: key.length === 1 ? (/[a-z]/i.test(key) ? "Key" + key.toUpperCase() : "Digit0") : key, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code };
      await send("Input.dispatchKeyEvent", { type: named[ch] ? "rawKeyDown" : "keyDown", ...base, text: named[ch] ? (key === "Enter" ? "\r" : undefined) : ch, unmodifiedText: named[ch] ? undefined : ch });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
      await sleep(Number(process.env.KEY_GAP || 150));
    }
    log("tasten gesendet:", process.env.KEYS.length);
  }
  // CHORDS="ctrl+r;ctrl+shift+z;enter;tab;escape;f5": key chords sent after KEYS (modifiers ctrl/shift/alt/meta, keys: a letter/digit,
  // enter, tab, escape, backspace, delete, space, up/down/left/right, home, end, pageup/pagedown, f1..f12), CHORD_GAP ms apart (default 600).
  // CLIPBOARD_SET="text": put text on the browser clipboard before any input (needs CLIPBOARD=1 for the permission).
  const setClipboard = async () => {
    if (!process.env.CLIPBOARD_SET) return;
    const r = await send("Runtime.evaluate", { expression: `navigator.clipboard.writeText(${JSON.stringify(process.env.CLIPBOARD_SET)}).then(() => 'set', e => 'ERR ' + e.message)`, awaitPromise: true, returnByValue: true, userGesture: true });
    log("clipboard set:", r.result?.result?.value);
  };
  const runChords = async (spec, delayMs, withPaste = true) => {
    const MODS = { alt: 1, ctrl: 2, meta: 4, shift: 8 };
    const NAMED = { enter: ["Enter", 13, "Enter", "\r"], tab: ["Tab", 9, "Tab", "\t"], escape: ["Escape", 27, "Escape"], backspace: ["Backspace", 8, "Backspace"],
      delete: ["Delete", 46, "Delete"], space: [" ", 32, "Space", " "], up: ["ArrowUp", 38, "ArrowUp"], down: ["ArrowDown", 40, "ArrowDown"],
      left: ["ArrowLeft", 37, "ArrowLeft"], right: ["ArrowRight", 39, "ArrowRight"], home: ["Home", 36, "Home"], end: ["End", 35, "End"],
      pageup: ["PageUp", 33, "PageUp"], pagedown: ["PageDown", 34, "PageDown"] };
    for (let i = 1; i <= 12; i++) NAMED["f" + i] = ["F" + i, 111 + i, "F" + i];
    await sleep(delayMs);
    await setClipboard();
    // PASTE_EVENT="text": dispatch a synthetic DOM paste event first (what a real Ctrl+V does as the default action of the keydown;
    // DevTools key events cannot trigger it for non-editable focus targets).  Frames: the event goes to every same-origin frame document.
    if (process.env.PASTE_EVENT && withPaste) {
      let pasteText = process.env.PASTE_EVENT;
      if (pasteText === "@clipboard") {   // PASTE_EVENT=@clipboard: use what is really on the browser clipboard
        const r = await send("Runtime.evaluate", { expression: "navigator.clipboard.readText().catch(e => '')", awaitPromise: true, returnByValue: true, userGesture: true });
        pasteText = r.result?.result?.value ?? "";
        log("clipboard text for paste:", JSON.stringify(pasteText));
      }
      const code = `(()=>{const T=${JSON.stringify(pasteText)};const fire=d=>{const dt=new DataTransfer();dt.setData('text/plain',T);d.dispatchEvent(new ClipboardEvent('paste',{clipboardData:dt,bubbles:true,cancelable:true}));};fire(document);for(const f of document.querySelectorAll('iframe')){try{fire(f.contentDocument)}catch(e){}}})()`;
      await send("Runtime.evaluate", { expression: code, returnByValue: true });
      log("paste event dispatched");
    }
    for (const chord of spec.split(";")) {
      const parts = chord.toLowerCase().split("+"); const k = parts.pop();
      const modifiers = parts.reduce((m, p) => m | (MODS[p] ?? 0), 0);
      let key, vk, code, text;
      if (NAMED[k]) [key, vk, code, text] = NAMED[k];
      else { key = (modifiers & 8) ? k.toUpperCase() : k; vk = k.toUpperCase().charCodeAt(0); code = /[a-z]/.test(k) ? "Key" + k.toUpperCase() : "Digit" + k; text = (modifiers & (1 | 2 | 4)) ? undefined : key; }
      // editing chords also need the browser "command" or the page never sees copy/cut/paste/selectAll events
      const commands = (modifiers & 2) ? ({ v: ["paste"], c: ["copy"], x: ["cut"], a: ["selectAll"], z: ["undo"] }[k] ?? undefined) : undefined;
      const base = { key, code, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk, modifiers, ...(commands ? { commands } : {}) };
      // modifier keys themselves first (Qt needs the modifier state, and some handlers watch the modifier key events)
      for (const [name, bit] of Object.entries(MODS)) if (modifiers & bit) await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: { alt: "Alt", ctrl: "Control", meta: "Meta", shift: "Shift" }[name], code: { alt: "AltLeft", ctrl: "ControlLeft", meta: "MetaLeft", shift: "ShiftLeft" }[name], windowsVirtualKeyCode: { alt: 18, ctrl: 17, meta: 91, shift: 16 }[name], modifiers });
      await send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...base, ...(text ? { text, unmodifiedText: text } : {}) });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
      for (const [name, bit] of Object.entries(MODS)) if (modifiers & bit) await send("Input.dispatchKeyEvent", { type: "keyUp", key: { alt: "Alt", ctrl: "Control", meta: "Meta", shift: "Shift" }[name], code: { alt: "AltLeft", ctrl: "ControlLeft", meta: "MetaLeft", shift: "ShiftLeft" }[name], windowsVirtualKeyCode: { alt: 18, ctrl: 17, meta: 91, shift: 16 }[name], modifiers: 0 });
      log("chord", chord);
      await sleep(Number(process.env.CHORD_GAP || 600));
    }
  };
  if (process.env.CHORDS) await runChords(process.env.CHORDS, Number(process.env.CHORDS_DELAY || 500), process.env.PASTE_PHASE !== "2");
  // KEYS2: more text typed after CHORDS (e.g. a file name into the dialog the chord opened); CHORDS2: chords after KEYS2.
  const typeText = async (text) => {
    const named = { "\n": ["Enter", 13], "\b": ["Backspace", 8] };
    for (const ch of text) {
      const [key, code] = named[ch] ?? [ch, ch.toUpperCase().charCodeAt(0)];
      const base = { key, code: key.length === 1 ? (/[a-z]/i.test(key) ? "Key" + key.toUpperCase() : "Digit0") : key, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code };
      await send("Input.dispatchKeyEvent", { type: named[ch] ? "rawKeyDown" : "keyDown", ...base, text: named[ch] ? (key === "Enter" ? "\r" : undefined) : ch, unmodifiedText: named[ch] ? undefined : ch });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
      await sleep(Number(process.env.KEY_GAP || 150));
    }
  };
  // CLICK_AT_C: clicks between the chords and KEYS2 (e.g. focus the file-name field of the dialog a chord opened).
  if (process.env.CLICK_AT_C) {
    await sleep(Number(process.env.CLICK_AT_C_DELAY || 1500));
    for (const pt of process.env.CLICK_AT_C.split(";")) { const [x, y] = pt.split(",").map(Number); await glideClick(x, y); log("klickC", x, y); await sleep(800); }
  }
  if (process.env.KEYS2) { await sleep(Number(process.env.KEYS2_DELAY || 800)); await typeText(process.env.KEYS2.replace(/\\n/g, "\n")); log("keys2 gesendet"); }
  if (process.env.CHORDS2) await runChords(process.env.CHORDS2, Number(process.env.CHORDS2_DELAY || 800), process.env.PASTE_PHASE === "2");
  // COPY_EVENT=copy|cut: dispatch a synthetic copy/cut event (what SEB's private clipboard triggers) and print what the page put into
  // clipboardData and whether it prevented the default (HACKING §85.18).
  if (process.env.COPY_EVENT) {
    const r = await send("Runtime.evaluate", { returnByValue: true, expression: `(()=>{const w=(document.querySelector('iframe')?.contentWindow)||window;const dt=new w.DataTransfer();
      const ev=new w.ClipboardEvent(${JSON.stringify(process.env.COPY_EVENT)},{clipboardData:dt,bubbles:true,cancelable:true});(w.document.activeElement||w.document.body).dispatchEvent(ev);
      return 'prevented='+ev.defaultPrevented+' text='+JSON.stringify(dt.getData('text/plain'));})()` });
    log("COPY_EVENT:", r.result?.result?.value ?? JSON.stringify(r.result));
  }
  // DOM_DUMP=1: print the frame's DOM outline and the active element (keyboard-focus diagnostics), at the end of the run.
  if (process.env.DOM_DUMP) {
    const r = await send("Runtime.evaluate", { returnByValue: true, expression: `(()=>{const d=(document.querySelector('iframe')?.contentDocument)||document;
      const desc=e=>e?(e.tagName+(e.id?'#'+e.id:'')+(e.className&&typeof e.className==='string'?'.'+e.className:'')+(e.getAttribute&&e.getAttribute('tabindex')!==null?'[tabindex='+e.getAttribute('tabindex')+']':'')+(e.isContentEditable?'[editable]':'')):'null';
      const walk=(e,dep)=>dep>5?'':desc(e)+'\\n'+[...e.children].map(c=>'  '.repeat(dep+1)+walk(c,dep+1)).join('');
      const c=d.getElementById('qt-shadow-container');const sr=c&&c.shadowRoot;const shadow=sr?('shadowActive='+desc(sr.activeElement)+' shadowHTML='+sr.innerHTML.slice(0,900)):'(no open shadowRoot)';return shadow+' || container='+(c?c.cloneNode(false).outerHTML:'none')+' topActive='+desc(document.activeElement)+' frameActive='+desc(d.activeElement)+' hasFocus='+d.hasFocus()+'\\n'+walk(d.body,0);})()` });
    log("DOM:\n" + (r.result?.result?.value ?? JSON.stringify(r.result)));
  }
  // MEM_DUMP=1: what the page's memory consists of -- WASM heap size, MEMFS content, JS heap, user-agent memory estimate (HACKING §85.19).
  if (process.env.MEM_DUMP) {
    const r = await send("Runtime.evaluate", { awaitPromise: true, returnByValue: true, expression: `(async()=>{const w=(document.querySelector('iframe')?.contentWindow)||window;const o={};
      const M=w.Module||w.qtModule||null;o.hasModule=!!M;
      try{o.heapMB=((M&&M.HEAPU8?M.HEAPU8.length:w.HEAPU8.length)/1048576).toFixed(0);}catch(e){o.heapErr=String(e)}
      try{const FS=(M&&M.FS)||w.FS;let tot=0,n=0;const walk=p=>{for(const e of FS.readdir(p)){if(e=='.'||e=='..')continue;const f=p=='/'?'/'+e:p+'/'+e;const st=FS.stat(f);if(FS.isDir(st.mode))walk(f);else{tot+=st.size;n++}}};walk('/');o.memfsMB=(tot/1048576).toFixed(0);o.memfsFiles=n;}catch(e){o.fsErr=String(e)}
      try{o.jsHeapMB=(w.performance.memory.usedJSHeapSize/1048576).toFixed(0)}catch(e){}
      try{const m=await w.performance.measureUserAgentSpecificMemory();o.uaMB=(m.bytes/1048576).toFixed(0);o.uaBreakdown=m.breakdown.filter(b=>b.bytes>5e6).map(b=>(b.bytes/1048576).toFixed(0)+'MB '+(b.types||[]).join('/'));}catch(e){o.uaErr=String(e)}
      return JSON.stringify(o);})()` });
    log("MEM:", r.result?.result?.value ?? JSON.stringify(r.result));
  }
  // IDLE_SAMPLE=<seconds> (after IDLE_AFTER seconds, default 0): resource use of the whole headless-Chrome process group while the page sits idle
  // -- CPU time delta / wall time (100 % = one core), RSS sum, process count; plus the page's own memory estimate (needs cross-origin isolation).
  if (process.env.IDLE_SAMPLE) {
    await sleep(Number(process.env.IDLE_AFTER || 0) * 1000);
    const snap = () => {
      const rows = execSync(`ps -axo pgid=,pid=,rss=,time=,command=`).toString().split("\n").filter((l) => l.trim());
      let rss = 0, cpu = 0, n = 0; const parts = [];
      for (const l of rows) {
        const m = l.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+([\d:.]+)\s+(.*)$/);
        if (!m || Number(m[1]) !== chrome.pid) continue;
        const t = m[4].split(":").reverse().reduce((a, v, i) => a + parseFloat(v) * Math.pow(60, i), 0);
        rss += Number(m[3]); cpu += t; n++;
        const kind = (m[5].match(/--type=(\w[\w-]*)/) || [, "browser"])[1] + (/--renderer-client-id/.test(m[5]) ? "" : "");
        parts.push({ pid: Number(m[2]), kind, t, rss: Number(m[3]) });
      }
      return { rss, cpu, n, parts, wall: Date.now() / 1000 };
    };
    const a = snap(); await sleep(Number(process.env.IDLE_SAMPLE) * 1000); const b = snap();
    const dw = b.wall - a.wall;
    log(`IDLE ${process.env.IDLE_SAMPLE}s: CPU ${(100 * (b.cpu - a.cpu) / dw).toFixed(1)} % of one core, RSS ${(b.rss / 1024).toFixed(0)} MB, ${b.n} processes`);
    const byKind = {};
    for (const q of b.parts) { const p0 = a.parts.find((x) => x.pid === q.pid); const d = p0 ? q.t - p0.t : q.t; (byKind[q.kind] ??= { cpu: 0, rss: 0, n: 0 }); byKind[q.kind].cpu += d; byKind[q.kind].rss += q.rss; byKind[q.kind].n++; }
    for (const [k, v] of Object.entries(byKind)) log(`  ${k.padEnd(10)} n=${v.n}  CPU ${(100 * v.cpu / dw).toFixed(1)} %  RSS ${(v.rss / 1024).toFixed(0)} MB`);
    const mem = await send("Runtime.evaluate", { expression: "(typeof performance.measureUserAgentSpecificMemory==='function'?performance.measureUserAgentSpecificMemory().then(r=>Math.round(r.bytes/1048576)+' MB (page estimate), '+r.breakdown.filter(b=>b.bytes>1048576).map(b=>Math.round(b.bytes/1048576)+' MB '+(b.types||[]).join('/')).join('; ')).catch(e=>'n/a: '+e.message):'n/a')", awaitPromise: true, returnByValue: true });
    log("  page memory:", mem.result?.result?.value);
  }
  // CLICK_AT2: clicks sent AFTER the keys (e.g. type code, then press Run).
  if (process.env.CLICK_AT2) {
    await sleep(Number(process.env.CLICK2_DELAY || 500));
    for (const pt of process.env.CLICK_AT2.split(";")) {
      const [x, y] = pt.split(",").map(Number);
      await glideClick(x, y);
      log("klick2", x, y);
      await sleep(1500);
    }
  }
  await sleep(Number(process.env.EXTRA_WAIT || 0) * 1000);
  if (process.env.CLIPBOARD) {
    const r = await send("Runtime.evaluate", { expression: "navigator.clipboard.readText().catch(e => 'ERR ' + e.message)", awaitPromise: true, returnByValue: true, userGesture: true });
    log("clipboard:", JSON.stringify(r.result?.result?.value));
  }
  log(done ? "fertig" : "TIMEOUT", ((Date.now() - t0) / 1000).toFixed(1) + " s");
  writeFileSync(`${OUT}/bench.json`, JSON.stringify(await ev("JSON.stringify(window.__bench||null)")) );
  writeFileSync(`${OUT}/console.txt`, cons.join("\n"));
  const shot = await send("Page.captureScreenshot", { format: "png" }); writeFileSync(`${OUT}/screenshot.png`, Buffer.from(shot.result.data, "base64"));
  console.log(await ev("JSON.stringify(window.__bench||null)")); ws.close();
} catch (e) { console.error("FEHLER:", e.message); process.exitCode = 1; }
finally { killChrome(); srv.close(); log("beendet"); setTimeout(() => process.exit(), 200); }
