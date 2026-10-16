// Qt-WASM + Racket CS in one module. Qt runs on the browser main thread (QApplication, widgets, exec());
// Racket's entry point (racket_em_main = main_em.c's main, renamed at compile time) runs in its own pthread.
// Spike content: Racket runs /app/main.rkt, which drives the shim through the FFI (see test/ffi-smoke.rkt).
#include <QApplication>
#include <QKeyEvent>
#include <QWidget>
#include <QPushButton>
#include <emscripten.h>
#include <pthread.h>
#include <cstdio>
#include <cstdlib>

extern "C" int racket_em_main(int argc, char** argv);
extern "C" void shim_app_init(void);   // the real shim, called here on the Qt thread

// Browser -> Qt clipboard bridge (HACKING §85.16).  Qt-WASM's own `paste` handling (QWasmClipboard::sendClipboardData) stores the text
// but then synthesizes a plain "V" key press, which DrRacket's editor inserts as a literal V instead of pasting.  A capture-phase
// listener on `window` (registered BEFORE Qt starts, so it runs first) hands the text to the shim's clipboard mirror (shim_clipboard_wasm_inject) itself and stops the event
// for Qt's listener.  The real Ctrl/Cmd+V key press already reaches the editor and pastes: the browser dispatches `paste` as the
// default action of that keydown, i.e. before the Racket thread has handled the key, so the cache is fresh when it asks.
extern "C" void shim_clipboard_wasm_inject(const char* utf8);   // shim.cpp: the WASM clipboard-text mirror
extern "C" void rqt_on_browser_paste(const char* text) {
    shim_clipboard_wasm_inject(text);
    // Qt-WASM does not forward the real Ctrl/Cmd+V key press (it waits for the paste event and synthesizes the key itself -- with an upper-case
    // "V", which the editor inserts as a letter).  Do the same, but as a proper Ctrl+v so that racket/gui's keymap pastes.
    if (QWidget* w = QApplication::focusWidget()) {
        QCoreApplication::postEvent(w, new QKeyEvent(QEvent::KeyPress,   Qt::Key_V, Qt::ControlModifier, QStringLiteral("v")));
        QCoreApplication::postEvent(w, new QKeyEvent(QEvent::KeyRelease, Qt::Key_V, Qt::ControlModifier, QStringLiteral("v")));
    }
}

static void* racket_thread(void*) {
    // Spike: Racket looks the shim up through (ffi-lib #f) -- the proxied entry points are registered by boot.c.
    // racket/gui picks its backend from the environment (gui-lib mred/private/wx/platform.rkt): the Qt backend.
    setenv("PLT_QT", "1", 1);
    // The program is preloaded as /app/main.rkt (CMake option RACKET_QT_MAIN, default test/ffi-smoke.rkt).
    static char a0[] = "racket", a1[] = "-I", a2[] = "racket/base", a3[] = "-e";
    static char a4[] = "(load \"/app/main.rkt\")";
    char* argv[] = { a0, a1, a2, a3, a4, nullptr };
    int rc = racket_em_main(5, argv);
    fprintf(stderr, "racket_em_main returned %d\n", rc);
    return nullptr;
}

int main(int argc, char** argv) {
    // Diagnostics: open the page with ?qtdebug to turn on the shim's PLT_QT_DEBUG output (mouse targets, paint regions, ...).
    if (MAIN_THREAD_EM_ASM_INT({ return new URLSearchParams(location.search).has('qtdebug') ? 1 : 0; }))
        setenv("PLT_QT_DEBUG", "1", 1);
    MAIN_THREAD_EM_ASM({
        window.addEventListener('paste', function(e) {
            var t = e.clipboardData ? e.clipboardData.getData('text/plain') : '';
            if (!t) return;
            e.preventDefault();
            e.stopImmediatePropagation();
            var n = lengthBytesUTF8(t) + 1, p = _malloc(n);
            stringToUTF8(t, p, n);
            getWasmTableEntry($0)(p);
            _free(p);
        }, true);
    }, (int)&rqt_on_browser_paste);
    shim_app_init();   // creates the QApplication (shim-owned); later proxied shim_app_init calls are no-ops
    (void)argc; (void)argv;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
    pthread_t th;
    pthread_create(&th, &attr, racket_thread, nullptr);

    // Marker for tools/serve-and-run.mjs (it waits for this title, then collects console output + a screenshot).
    MAIN_THREAD_EM_ASM({ document.title = 'BENCH-DONE'; });

    return QApplication::exec();   // Qt-WASM standard; the browser owns the loop (docs/HACKING.md §85.1)
}
