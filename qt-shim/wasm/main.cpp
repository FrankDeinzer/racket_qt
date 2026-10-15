// Qt-WASM + Racket CS in one module. Qt runs on the browser main thread (QApplication, widgets, exec());
// Racket's entry point (racket_em_main = main_em.c's main, renamed at compile time) runs in its own pthread.
// Spike content: a Qt window plus a Racket process that evaluates one expression.
#include <QApplication>
#include <QPushButton>
#include <emscripten.h>
#include <pthread.h>
#include <cstdio>

extern "C" int racket_em_main(int argc, char** argv);

static void* racket_thread(void*) {
    static char a0[] = "racket", a1[] = "-I", a2[] = "racket/base", a3[] = "-e";
    static char a4[] = "(begin (displayln \"racket-in-pthread: hello\") (displayln (+ 1 2)))";
    char* argv[] = { a0, a1, a2, a3, a4, nullptr };
    int rc = racket_em_main(5, argv);
    fprintf(stderr, "racket_em_main returned %d\n", rc);
    return nullptr;
}

int main(int argc, char** argv) {
    QApplication app(argc, argv);
    QPushButton b("qt + racket (wasm)");
    b.resize(300, 60);
    b.show();

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
    pthread_t th;
    pthread_create(&th, &attr, racket_thread, nullptr);

    // Marker for tools/serve-and-run.mjs (it waits for this title, then collects console output + a screenshot).
    MAIN_THREAD_EM_ASM({ document.title = 'BENCH-DONE'; });

    return app.exec();   // Qt-WASM standard; the browser owns the loop (docs/HACKING.md §85.1)
}
