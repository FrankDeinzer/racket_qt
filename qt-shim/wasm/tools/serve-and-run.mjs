// Static COOP/COEP server + headless Chrome (DevTools protocol, Node built-ins only) for the WASM builds.
// CHROME_GPU=1: no SwiftShader flags (real GPU via ANGLE/Metal); logs UNMASKED_RENDERER so the result says which renderer ran.
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
const chrome = spawn(CHROME, ["--headless=new", `--remote-debugging-port=${PORT}`, "--remote-debugging-address=127.0.0.1", `--user-data-dir=${OUT}/profile`, "--no-first-run", "--window-size=1100,900", ...(process.env.CHROME_GPU ? ["--enable-gpu", "--ignore-gpu-blocklist"] : ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]), "about:blank"], { stdio: "ignore" });
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
  if (process.env.CHORDS) {
    const MODS = { alt: 1, ctrl: 2, meta: 4, shift: 8 };
    const NAMED = { enter: ["Enter", 13, "Enter", "\r"], tab: ["Tab", 9, "Tab", "\t"], escape: ["Escape", 27, "Escape"], backspace: ["Backspace", 8, "Backspace"],
      delete: ["Delete", 46, "Delete"], space: [" ", 32, "Space", " "], up: ["ArrowUp", 38, "ArrowUp"], down: ["ArrowDown", 40, "ArrowDown"],
      left: ["ArrowLeft", 37, "ArrowLeft"], right: ["ArrowRight", 39, "ArrowRight"], home: ["Home", 36, "Home"], end: ["End", 35, "End"],
      pageup: ["PageUp", 33, "PageUp"], pagedown: ["PageDown", 34, "PageDown"] };
    for (let i = 1; i <= 12; i++) NAMED["f" + i] = ["F" + i, 111 + i, "F" + i];
    await sleep(Number(process.env.CHORDS_DELAY || 500));
    for (const chord of process.env.CHORDS.split(";")) {
      const parts = chord.toLowerCase().split("+"); const k = parts.pop();
      const modifiers = parts.reduce((m, p) => m | (MODS[p] ?? 0), 0);
      let key, vk, code, text;
      if (NAMED[k]) [key, vk, code, text] = NAMED[k];
      else { key = (modifiers & 8) ? k.toUpperCase() : k; vk = k.toUpperCase().charCodeAt(0); code = /[a-z]/.test(k) ? "Key" + k.toUpperCase() : "Digit" + k; text = (modifiers & (1 | 2 | 4)) ? undefined : key; }
      const base = { key, code, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk, modifiers };
      // modifier keys themselves first (Qt needs the modifier state, and some handlers watch the modifier key events)
      for (const [name, bit] of Object.entries(MODS)) if (modifiers & bit) await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: { alt: "Alt", ctrl: "Control", meta: "Meta", shift: "Shift" }[name], code: { alt: "AltLeft", ctrl: "ControlLeft", meta: "MetaLeft", shift: "ShiftLeft" }[name], windowsVirtualKeyCode: { alt: 18, ctrl: 17, meta: 91, shift: 16 }[name], modifiers });
      await send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...base, ...(text ? { text, unmodifiedText: text } : {}) });
      await send("Input.dispatchKeyEvent", { type: "keyUp", ...base });
      for (const [name, bit] of Object.entries(MODS)) if (modifiers & bit) await send("Input.dispatchKeyEvent", { type: "keyUp", key: { alt: "Alt", ctrl: "Control", meta: "Meta", shift: "Shift" }[name], code: { alt: "AltLeft", ctrl: "ControlLeft", meta: "MetaLeft", shift: "ShiftLeft" }[name], windowsVirtualKeyCode: { alt: 18, ctrl: 17, meta: 91, shift: 16 }[name], modifiers: 0 });
      log("chord", chord);
      await sleep(Number(process.env.CHORD_GAP || 600));
    }
  }
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
  log(done ? "fertig" : "TIMEOUT", ((Date.now() - t0) / 1000).toFixed(1) + " s");
  writeFileSync(`${OUT}/bench.json`, JSON.stringify(await ev("JSON.stringify(window.__bench||null)")) );
  writeFileSync(`${OUT}/console.txt`, cons.join("\n"));
  const shot = await send("Page.captureScreenshot", { format: "png" }); writeFileSync(`${OUT}/screenshot.png`, Buffer.from(shot.result.data, "base64"));
  console.log(await ev("JSON.stringify(window.__bench||null)")); ws.close();
} catch (e) { console.error("FEHLER:", e.message); process.exitCode = 1; }
finally { chrome.kill("SIGTERM"); srv.close(); await sleep(500); if (chrome.exitCode === null) chrome.kill("SIGKILL"); log("beendet"); setTimeout(() => process.exit(), 200); }
