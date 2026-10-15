#!/usr/bin/env python3
"""Generate the WASM thread-proxy layer for qt-shim/src/shim.cpp (docs/HACKING.md §85.1).

In the combined Qt+Racket WASM module Qt lives on the browser main thread and Racket in a pthread, so
 * every `shim_*` call from Racket must run on the main thread  -> a synchronous proxy wrapper per function;
 * Qt calls the callbacks Racket passed in on the main thread, but a Racket FFI closure only works in the
   thread that made it (libffi closure table is per worker)  -> the shim gets a C trampoline that enqueues
   the call; the Racket thread runs the queue from `shim_pump` (a Racket-thread dispatcher, not processEvents).

Reads shim.cpp's extern "C" block (callback typedefs + function definitions) and writes, into <outdir>:
  shim_wasm_proxy.cpp   wrappers W_shim_*, trampolines, queue, W_shim_pump / W_shim_events_pending
  wasm_shim.inc         `{ extern void W_x(); Sforeign_symbol("x", (void*)W_x); }` lines for boot.c's init_foreign
  rqt_wasm_extras.inc   wrapper: the fork's wasm_extras.inc, then wasm_shim.inc (own name: a quoted #include in boot.c
                        searches boot.c's own directory first, where the fork's wasm_extras.inc would shadow it)

usage: gen-proxies.py <shim.cpp> <fork wasm_extras.inc> <outdir>
"""
import re
import sys
import os

src_path, fork_extras, outdir = sys.argv[1:4]
text = open(src_path, encoding="utf-8").read()

# ---- callback typedefs: typedef void (*NAME)(args); ------------------------------------------------------
cb_types = {}
for m in re.finditer(r"^typedef\s+void\s*\(\*\s*(\w+)\)\s*\(([^)]*)\)\s*;", text, re.M):
    cb_types[m.group(1)] = m.group(2).strip()


def split_args(s):
    s = s.strip()
    if s in ("", "void"):
        return []
    return [a.strip() for a in s.split(",")]


_PRIM = {"int", "void", "char", "double", "float", "long", "short", "unsigned", "uint8_t", "const", "signed"}


def parse_param(p, idx=0):
    """Split `type name` (name may be missing: `void*`, `int`) -> (type, name)."""
    toks = re.findall(r"[A-Za-z_]\w*|\*", p)
    if len(toks) > 1 and toks[-1] != "*" and toks[-1] not in _PRIM:
        name = toks[-1]
        typ = p.rsplit(name, 1)[0].strip()
        return typ, name
    return p.strip(), "a%d" % idx


# ---- function definitions inside the extern "C" block ----------------------------------------------------
start = text.index('extern "C" {')
body = text[start:]
func_re = re.compile(
    r"^(?P<ret>[A-Za-z_][A-Za-z0-9_ \t\*]*?)[ \t\*]\b(?P<name>shim_\w+)\s*\((?P<args>[^()]*)\)\s*\{", re.M)
funcs = []
for m in func_re.finditer(body):
    ret = m.group("ret").strip()
    if ret.startswith("static") or ret.startswith("inline"):
        continue
    # keep the '*' that belongs to the return type
    full = body[m.start():m.end()]
    ret_full = full.split(m.group("name"))[0].strip()
    funcs.append((ret_full, m.group("name"), split_args(m.group("args"))))

# shim exports that delete their widget: the records registered for it are released with it
DESTROY = {"shim_window_destroy", "shim_canvas_destroy", "shim_button_destroy", "shim_printer_destroy"}
# Only these registrations are released (replace / destroy). Each one was read in shim.cpp: the callback + ud are stored in a
# member of the object (or an event filter that is deleted on replace), so after a replace/destroy nothing in Qt still points
# at the old record. Everything else (setters that connect() a lambda or install a NEW event filter per call, one-shot dialogs,
# widgets that are never destroyed explicitly) keeps the old behaviour: a record that is never freed. Add a name here only
# after checking that.
RELEASABLE = {
    "shim_app_set_quit_cb",
    "shim_canvas_set_focus_cb", "shim_canvas_set_key_cb", "shim_canvas_set_mouse_cb", "shim_canvas_set_wheel_cb",
    "shim_menu_set_about_to_hide_cb", "shim_menu_set_about_to_show_cb",
    "shim_widget_set_drop_cb",
    "shim_window_set_activate_cb", "shim_window_set_drop_cb", "shim_window_set_move_cb", "shim_window_set_resize_cb",
    # created together with the widget, released with its explicit destroy (shim_*_destroy deletes the widget at once)
    "shim_window_create", "shim_canvas_create", "shim_button_create",
}
SPECIAL = {"shim_pump", "shim_pump_us", "shim_events_pending", "shim_app_quit"}
# Platform variants (#ifdef __linux__ ... #else stub) define a few functions twice; they must agree on the parameter
# TYPES (names may differ or be missing in the stub). Keep the variant whose parameters are all named.
PRIMS = {"int", "void", "char", "double", "float", "long", "short", "unsigned", "uint8_t", "const", "signed"}


def type_of(p):
    toks = re.findall(r"[A-Za-z_]\w*|\*", p)
    if toks and toks[-1] != "*" and toks[-1] not in PRIMS and len(toks) > 1 and not all(t in PRIMS or t == "*" for t in toks):
        toks = toks[:-1]          # drop the parameter name
    return " ".join(toks)


def all_named(args):
    return all(re.match(r"^.*[\s\*]\w+$", a) and not all(t in PRIMS or t == "*" for t in re.findall(r"[A-Za-z_]\w*|\*", a))
               for a in args)


by_name = {}
for f in funcs:
    sig = (f[0].replace(" ", ""), tuple(type_of(a).replace(" ", "") for a in f[2]))
    if f[1] in by_name:
        old_f, old_sig = by_name[f[1]]
        if old_sig != sig:
            raise SystemExit("%s is defined twice with different signatures: %s vs %s" % (f[1], old_sig, sig))
        if all_named(f[2]) and not all_named(old_f[2]):
            by_name[f[1]] = (f, sig)
        continue
    by_name[f[1]] = (f, sig)
funcs = [v[0] for v in by_name.values()]

out = []
w = out.append
w("// AUTO-GENERATED by tools/gen-proxies.py from shim.cpp -- do not edit.")
w("#include <cstdint>")
w("#include <cstdlib>")
w("#include <cstring>")
w("#include <string>")
w("#include <deque>")
w("#include <functional>")
w("#include <mutex>")
w("#include <atomic>")
w("#include <map>")
w("#include <emscripten.h>")
w("#include <emscripten/threading.h>")
w("#include <emscripten/proxying.h>")
w("")
for name, args in cb_types.items():
    w("typedef void (*%s)(%s);" % (name, args))
w("")
w('extern "C" {')
for ret, name, args in funcs:
    w("%s %s(%s);" % (ret, name, ", ".join(args) if args else "void"))
w("}")
w("")
w("""namespace {
emscripten::ProxyingQueue g_proxy;
template <class F> inline void on_main(F&& f) {
    if (emscripten_is_main_runtime_thread()) f();
    else g_proxy.proxySync(emscripten_main_runtime_thread_id(), std::forward<F>(f));
}

// Callback queue: filled on the Qt (main) thread, drained by the Racket thread inside W_shim_pump.
std::mutex g_cb_mu;
std::deque<std::function<void()>> g_cb_q;
inline void post_cb(std::function<void()> f) {
    std::lock_guard<std::mutex> lk(g_cb_mu);
    g_cb_q.push_back(std::move(f));
}

// Callback records (HACKING §85.12). A record {racket_cb, racket_ud} is owned by the registry below, keyed by
// (widget handle, setter name[#n]); re-registering or destroying the widget releases it. refs counts the registry's own
// reference plus one per callback queued for the Racket thread, so a record is never freed under a queued call.
// The registry is only touched on the Qt thread (inside on_main), like the shim itself.
std::atomic<int> g_rec_live{0};   // live records, for shim_rec_count (leak check in test/rec-leak.rkt)
struct RecBase {
    std::atomic<int> refs{1};
    RecBase() { g_rec_live.fetch_add(1); }
    virtual ~RecBase() { g_rec_live.fetch_sub(1); }
};
inline void rec_release(RecBase* r) { if (r && r->refs.fetch_sub(1) == 1) delete r; }
std::map<void*, std::map<std::string, RecBase*>> g_recs;
inline void rec_set(void* handle, const char* key, RecBase* r) {
    auto& slot = g_recs[handle][key];
    if (slot != r) { rec_release(slot); slot = r; }
    if (!slot) g_recs[handle].erase(key);
}
inline void rec_drop_widget(void* handle) {
    auto it = g_recs.find(handle);
    if (it == g_recs.end()) return;
    for (auto& kv : it->second) rec_release(kv.second);
    g_recs.erase(it);
}
}  // namespace
""")

# trampolines: one per callback typedef; the Racket callback + its ud live in a heap record passed as ud.
for name, args in cb_types.items():
    params = split_args(args)
    typed = [parse_param(p, i) for i, p in enumerate(params)]
    if not typed or typed[0][0].replace(" ", "") != "void*":
        raise SystemExit("callback %s: first parameter must be the void* user data (%r)" % (name, args))
    rest = typed[1:]
    w("struct Rec_%s : RecBase { %s cb; void* ud; Rec_%s(%s c, void* u) : cb(c), ud(u) {} };" % (name, name, name, name))
    decl = ", ".join(["void* rec"] + ["%s %s" % (t, n) for t, n in rest])
    w("static void tramp_%s(%s) {" % (name, decl))
    w("    Rec_%s* rec__ = static_cast<Rec_%s*>(rec);" % (name, name))
    w("    rec__->refs.fetch_add(1);   // released after the queued call ran (the registry still holds its own reference here)")
    caps, call_args = [], ["rec__->ud"]
    for t, n in rest:
        if t.replace(" ", "") == "constchar*":
            caps.append("%s_s = std::string(%s ? %s : \"\"), %s_n = (%s != nullptr)" % (n, n, n, n, n))
            call_args.append("%s_n ? %s_s.c_str() : nullptr" % (n, n))
        else:
            caps.append("%s = %s" % (n, n))
            call_args.append(n)
    cap = ", ".join(["rec__"] + caps)
    w("    post_cb([%s] { rec__->cb(%s); rec_release(rec__); });" % (cap, ", ".join(call_args)))
    w("}")
    w("")

# wrappers
reg = []
for ret, name, args in funcs:
    if name in SPECIAL:
        continue
    typed = [parse_param(p, i) for i, p in enumerate(args)]
    decl = ", ".join("%s %s" % (t, n) for t, n in typed) if typed else "void"
    call = []
    pre, post = [], []
    ncb = 0
    # registry handle: the created widget (ret void*), else the widget the setter works on (first void* parameter),
    # else 0 (application-level setters such as shim_app_set_quit_cb)
    if ret.replace(" ", "") == "void*":
        handle = "rv__"
    elif typed and typed[0][0].replace(" ", "") == "void*":
        handle = typed[0][1]
    else:
        handle = "(void*)nullptr"
    i = 0
    while i < len(typed):
        t, n = typed[i]
        key = t.replace("const ", "").strip()
        if key in cb_types:
            if i + 1 >= len(typed) or typed[i + 1][0].replace(" ", "") != "void*":
                raise SystemExit("%s: callback parameter %s is not followed by a void* user data" % (name, n))
            un = typed[i + 1][1]
            rv = "r%d__" % ncb
            pre.append("Rec_%s* %s = %s ? new Rec_%s(%s, %s) : nullptr;" % (key, rv, n, key, n, un))
            call.append("%s ? (%s)tramp_%s : nullptr" % (n, key, key))
            call.append("%s ? (void*)%s : %s" % (n, rv, un))
            if name in RELEASABLE:
                post.append('rec_set(%s, "%s#%d", %s);' % (handle, name, ncb, rv))
            ncb += 1
            i += 2
            continue
        call.append(n)
        i += 1
    if name in DESTROY:
        post.append("rec_drop_widget(%s);" % typed[0][1])
    pre_s = " ".join(pre)
    post_s = " ".join(post)
    w('extern "C" %s W_%s(%s) {' % (ret, name, decl))
    if ret == "void":
        w("    on_main([&] { %s %s(%s); %s });" % (pre_s, name, ", ".join(call), post_s))
    else:
        w("    %s rv__{};" % ret)
        w("    on_main([&] { %s rv__ = %s(%s); %s });" % (pre_s, name, ", ".join(call), post_s))
        w("    return rv__;")
    w("}")
    reg.append(name)

w("""
// shim_pump on WASM: run the callbacks Qt queued (on this, the Racket, thread). Qt's own event loop belongs to
// the browser; never call processEvents from here. Returns after at most `max_ms` of work (no waiting).
extern "C" void W_shim_pump(int max_ms) {
    (void)max_ms;
    for (;;) {
        std::function<void()> f;
        {
            std::lock_guard<std::mutex> lk(g_cb_mu);
            if (g_cb_q.empty()) return;
            f = std::move(g_cb_q.front());
            g_cb_q.pop_front();
        }
        f();
    }
}
extern "C" int W_shim_events_pending(void) {
    std::lock_guard<std::mutex> lk(g_cb_mu);
    return g_cb_q.empty() ? 0 : 1;
}
extern "C" void W_shim_app_quit(void) { /* the browser owns the Qt application lifetime */ }
extern "C" long long W_shim_pump_us(int max_ms) { W_shim_pump(max_ms); return 0; }
extern "C" int W_shim_rec_count(void) { return g_rec_live.load(); }   // debug: number of live callback records
""")
reg += ["shim_pump", "shim_events_pending", "shim_app_quit", "shim_pump_us", "shim_rec_count"]

os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, "shim_wasm_proxy.cpp"), "w").write("\n".join(out) + "\n")

inc = ["/* AUTO-GENERATED by tools/gen-proxies.py -- do not edit. Registers the proxied shim_* entry points so Racket's",
       "   (ffi-lib #f) / get-ffi-obj can find them. Included by wasm_extras.inc inside boot.c's init_foreign. */"]
for n in reg:
    inc.append('{ extern void W_%s(); Sforeign_symbol("%s", (void *)W_%s); }' % (n, n, n))
open(os.path.join(outdir, "wasm_shim.inc"), "w").write("\n".join(inc) + "\n")

open(os.path.join(outdir, "rqt_wasm_extras.inc"), "w").write(
    '/* AUTO-GENERATED: the fork\'s wasm_extras.inc followed by the shim registrations. */\n'
    '#include "%s"\n'
    '#include "wasm_shim.inc"\n' % os.path.abspath(fork_extras))

sys.stderr.write("gen-proxies: %d functions, %d callback types, %d registered\n"
                 % (len(funcs), len(cb_types), len(reg)))
