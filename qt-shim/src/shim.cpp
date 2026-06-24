#include <QApplication>
#include <QMainWindow>
#include <QWidget>
#include <QPushButton>
#include <QVBoxLayout>
#include <QImage>
#include <QPainter>
#include <QResizeEvent>
#include <QPaintEvent>
#include <QShowEvent>
#include <QCloseEvent>
#include <cstdint>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#endif

extern "C" {

const char* shim_version(void)
{
    return "racketqtshim 0.1.0-spike";
}

typedef void (*shim_callback_t)(void* userdata);

static int    s_argc = 0;
static char** s_argv = nullptr;
static QApplication* s_app = nullptr;

// ---- RacketCanvas -------------------------------------------------------

class RacketCanvas : public QWidget {
public:
    QImage          backing;
    shim_callback_t expose_cb;
    void*           expose_ud;

    RacketCanvas(QWidget* parent, shim_callback_t cb, void* ud)
        : QWidget(parent), expose_cb(cb), expose_ud(ud)
    {
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        backing = QImage(1, 1, QImage::Format_ARGB32_Premultiplied);
        backing.fill(Qt::white);
    }

protected:
    void paintEvent(QPaintEvent*) override {
        QPainter p(this);
        if (!backing.isNull())
            p.drawImage(QRect(0, 0, width(), height()), backing);
    }

    void resizeEvent(QResizeEvent* e) override {
        QWidget::resizeEvent(e);
        if (expose_cb) expose_cb(expose_ud);
    }

    void showEvent(QShowEvent* e) override {
        QWidget::showEvent(e);
        if (expose_cb) expose_cb(expose_ud);
    }
};

// ---- RacketWindow -------------------------------------------------------

class RacketWindow : public QMainWindow {
public:
    shim_callback_t close_cb;
    void*           close_ud;

    RacketWindow(shim_callback_t cb, void* ud)
        : QMainWindow(nullptr), close_cb(cb), close_ud(ud)
    {
        setAttribute(Qt::WA_DeleteOnClose, false);
        QWidget* central = new QWidget(this);
        QVBoxLayout* layout = new QVBoxLayout(central);
        layout->setContentsMargins(4, 4, 4, 4);
        layout->setSpacing(4);
        setCentralWidget(central);
    }

    QLayout* contentLayout() {
        return centralWidget()->layout();
    }

protected:
    void closeEvent(QCloseEvent* e) override {
        e->ignore();
        if (close_cb) close_cb(close_ud);
    }
};

// ---- lifecycle ----------------------------------------------------------

void shim_app_init(void)
{
    if (s_app) return;
    qputenv("QT_SCALE_FACTOR", "1");
    QApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    static char prog[] = "racket";
    static char* argv_arr[] = { prog, nullptr };
    s_argc = 1;
    s_argv = argv_arr;
    s_app = new QApplication(s_argc, s_argv);
}

void shim_app_quit(void)
{
    delete s_app;
    s_app = nullptr;
}

void shim_pump(int max_ms)
{
    if (s_app)
        s_app->processEvents(QEventLoop::AllEvents, max_ms);
}

int shim_events_pending(void)
{
#ifdef _WIN32
    return (GetQueueStatus(QS_ALLINPUT) != 0) ? 1 : 0;
#else
    return 1;
#endif
}

// ---- window -------------------------------------------------------------

void* shim_window_create(shim_callback_t close_cb, void* ud)
{
    return new RacketWindow(close_cb, ud);
}

void shim_window_set_title(void* win, const char* title)
{
    static_cast<RacketWindow*>(win)->setWindowTitle(
        QString::fromUtf8(title));
}

void shim_window_set_size(void* win, int w, int h)
{
    static_cast<RacketWindow*>(win)->resize(w, h);
}

void shim_window_show(void* win, int visible)
{
    auto* rw = static_cast<RacketWindow*>(win);
    if (visible) rw->show(); else rw->hide();
}

void shim_window_destroy(void* win)
{
    delete static_cast<RacketWindow*>(win);
}

// ---- canvas -------------------------------------------------------------

void* shim_canvas_create(void*           parent_win,
                         shim_callback_t expose_cb,
                         void*           ud)
{
    auto* rw     = static_cast<RacketWindow*>(parent_win);
    auto* canvas = new RacketCanvas(nullptr, expose_cb, ud);
    canvas->setMinimumSize(1, 1);
    rw->contentLayout()->addWidget(canvas);
    return canvas;
}

void shim_canvas_blit_argb(void*          canvas_ptr,
                           const uint8_t* src,
                           int w, int h, int stride)
{
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    QImage img(w, h, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * stride;
        for (int x = 0; x < w; x++) {
            uint8_t a = src_row[x * 4 + 0];
            uint8_t r = src_row[x * 4 + 1];
            uint8_t g = src_row[x * 4 + 2];
            uint8_t b = src_row[x * 4 + 3];
            dst_row[x] = (uint32_t(a) << 24)
                       | (uint32_t(r) << 16)
                       | (uint32_t(g) <<  8)
                       |  uint32_t(b);
        }
    }
    c->backing = img;
}

void shim_canvas_request_repaint(void* canvas_ptr)
{
    static_cast<RacketCanvas*>(canvas_ptr)->update();
}

int shim_canvas_get_width(void* canvas_ptr)
{
    return static_cast<RacketCanvas*>(canvas_ptr)->width();
}

int shim_canvas_get_height(void* canvas_ptr)
{
    return static_cast<RacketCanvas*>(canvas_ptr)->height();
}

void shim_canvas_destroy(void* canvas_ptr)
{
    delete static_cast<RacketCanvas*>(canvas_ptr);
}

// ---- button -------------------------------------------------------------

void* shim_button_create(void*           parent_win,
                         const char*     label,
                         shim_callback_t click_cb,
                         void*           ud)
{
    auto* rw  = static_cast<RacketWindow*>(parent_win);
    auto* btn = new QPushButton(QString::fromUtf8(label));
    rw->contentLayout()->addWidget(btn);
    if (click_cb) {
        QObject::connect(btn, &QPushButton::clicked,
                         [click_cb, ud]() { click_cb(ud); });
    }
    return btn;
}

void shim_button_destroy(void* btn_ptr)
{
    delete static_cast<QPushButton*>(btn_ptr);
}

} // extern "C"
