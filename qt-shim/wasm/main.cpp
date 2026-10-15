// Qt-WASM + Racket CS in one module. Qt runs on the browser main thread (QApplication, widgets, exec());
// Racket's entry point (racket_em_main = main_em.c's main, renamed at compile time) runs in its own pthread.
// Spike content: Racket runs /app/main.rkt, which drives the shim through the FFI (see test/ffi-smoke.rkt).
#include <QApplication>
#include <QPushButton>
#include <emscripten.h>
#include <pthread.h>
#include <cstdio>
#include <cstdlib>

extern "C" int racket_em_main(int argc, char** argv);
extern "C" void shim_app_init(void);   // the real shim, called here on the Qt thread

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
