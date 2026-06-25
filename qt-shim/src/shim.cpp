#include <QApplication>
#include <QMainWindow>
#include <QWidget>
#include <QPushButton>
#include <QImage>
#include <QPainter>
#include <QResizeEvent>
#include <QPaintEvent>
#include <QShowEvent>
#include <QCloseEvent>
#include <QMouseEvent>
#include <QKeyEvent>
#include <QFocusEvent>
#include <QEnterEvent>
#include <cstdint>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#endif

extern "C" {

const char* shim_version(void)
{
    return "racketqtshim 0.2.0";
}

typedef void (*shim_callback_t)(void* userdata);
// Mouse: type(0=press,1=release,2=move,3=enter,4=leave), x, y, buttons(L=1,M=2,R=4), mods(Sh=1,Ct=2,Al=4,Me=8)
typedef void (*shim_mouse_cb_t)(void* ud, int type, int x, int y, int buttons, int mods);
// Key: type(0=press,1=release), Qt::Key, text char (unicode, 0 if none), mods
typedef void (*shim_key_cb_t)(void* ud, int type, int key, int text_char, int mods);
// Focus: gained(1=in, 0=out)
typedef void (*shim_focus_cb_t)(void* ud, int gained);

static int    s_argc = 0;
static char** s_argv = nullptr;
static QApplication* s_app = nullptr;

// ---- RacketCanvas -------------------------------------------------------

class RacketCanvas : public QWidget {
public:
    QImage          backing;
    shim_callback_t expose_cb;
    void*           expose_ud;
    shim_mouse_cb_t mouse_cb  = nullptr;
    void*           mouse_ud  = nullptr;
    shim_key_cb_t   key_cb    = nullptr;
    void*           key_ud    = nullptr;
    shim_focus_cb_t focus_cb  = nullptr;
    void*           focus_ud  = nullptr;

    RacketCanvas(QWidget* parent, shim_callback_t cb, void* ud)
        : QWidget(parent), expose_cb(cb), expose_ud(ud)
    {
        setMinimumSize(1, 1);
        setFocusPolicy(Qt::StrongFocus);
        setMouseTracking(true);
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

    // ---- mouse ----------------------------------------------------------

    static int encodeButtons(Qt::MouseButtons b) {
        int r = 0;
        if (b & Qt::LeftButton)   r |= 1;
        if (b & Qt::MiddleButton) r |= 2;
        if (b & Qt::RightButton)  r |= 4;
        return r;
    }
    static int encodeMods(Qt::KeyboardModifiers m) {
        int r = 0;
        if (m & Qt::ShiftModifier)   r |= 1;
        if (m & Qt::ControlModifier) r |= 2;
        if (m & Qt::AltModifier)     r |= 4;
        if (m & Qt::MetaModifier)    r |= 8;
        return r;
    }

    void mousePressEvent(QMouseEvent* e) override {
        // For press/release, pass e->button() (single triggering button) so
        // Racket always knows which button caused the event.
        if (mouse_cb)
            mouse_cb(mouse_ud, 0, (int)e->position().x(), (int)e->position().y(),
                     encodeButtons(Qt::MouseButtons(e->button())),
                     encodeMods(e->modifiers()));
    }
    void mouseReleaseEvent(QMouseEvent* e) override {
        if (mouse_cb)
            mouse_cb(mouse_ud, 1, (int)e->position().x(), (int)e->position().y(),
                     encodeButtons(Qt::MouseButtons(e->button())),
                     encodeMods(e->modifiers()));
    }
    void mouseMoveEvent(QMouseEvent* e) override {
        // For move, pass all currently held buttons.
        if (mouse_cb)
            mouse_cb(mouse_ud, 2, (int)e->position().x(), (int)e->position().y(),
                     encodeButtons(e->buttons()), encodeMods(e->modifiers()));
    }
    void enterEvent(QEnterEvent* e) override {
        QWidget::enterEvent(e);
        if (mouse_cb)
            mouse_cb(mouse_ud, 3, (int)e->position().x(), (int)e->position().y(),
                     0, 0);
    }
    void leaveEvent(QEvent* e) override {
        QWidget::leaveEvent(e);
        if (mouse_cb)
            mouse_cb(mouse_ud, 4, 0, 0, 0, 0);
    }

    // ---- keyboard -------------------------------------------------------

    void keyPressEvent(QKeyEvent* e) override {
        if (key_cb) {
            int tc = e->text().isEmpty() ? 0 : (int)e->text().at(0).unicode();
            key_cb(key_ud, 0, e->key(), tc, encodeMods(e->modifiers()));
        }
    }
    void keyReleaseEvent(QKeyEvent* e) override {
        if (key_cb) {
            int tc = e->text().isEmpty() ? 0 : (int)e->text().at(0).unicode();
            key_cb(key_ud, 1, e->key(), tc, encodeMods(e->modifiers()));
        }
    }

    // ---- focus ----------------------------------------------------------

    void focusInEvent(QFocusEvent* e) override {
        QWidget::focusInEvent(e);
        if (focus_cb) focus_cb(focus_ud, 1);
    }
    void focusOutEvent(QFocusEvent* e) override {
        QWidget::focusOutEvent(e);
        if (focus_cb) focus_cb(focus_ud, 0);
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
        // Plain content widget — Racket drives all child geometry via
        // shim_widget_set_geometry; no Qt layout manager involved.
        setCentralWidget(new QWidget(this));
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

// Returns the central QWidget* that child widgets (canvas, button, panel)
// should use as their Qt parent.
void* shim_window_get_content_widget(void* win)
{
    return static_cast<RacketWindow*>(win)->centralWidget();
}

// ---- geometry -----------------------------------------------------------

// Sets absolute position and size of any child QWidget.
// Called by Racket's layout engine after it computes positions.
void shim_widget_set_geometry(void* widget, int x, int y, int w, int h)
{
    static_cast<QWidget*>(widget)->setGeometry(x, y, w, h);
}

// ---- canvas -------------------------------------------------------------

void* shim_canvas_create(void*           parent_widget,
                         shim_callback_t expose_cb,
                         void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    return new RacketCanvas(parent, expose_cb, ud);
}

void shim_canvas_set_mouse_cb(void* canvas_ptr, shim_mouse_cb_t cb, void* ud)
{
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    c->mouse_cb = cb;
    c->mouse_ud = ud;
}

void shim_canvas_set_key_cb(void* canvas_ptr, shim_key_cb_t cb, void* ud)
{
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    c->key_cb = cb;
    c->key_ud = ud;
}

void shim_canvas_set_focus_cb(void* canvas_ptr, shim_focus_cb_t cb, void* ud)
{
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    c->focus_cb = cb;
    c->focus_ud = ud;
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

// ---- panel --------------------------------------------------------------

// Creates a plain container QWidget. Racket positions it via
// shim_widget_set_geometry; children of the panel parent themselves here.
void* shim_panel_create(void* parent_widget)
{
    return new QWidget(static_cast<QWidget*>(parent_widget));
}

// ---- button -------------------------------------------------------------

void* shim_button_create(void*           parent_widget,
                         const char*     label,
                         shim_callback_t click_cb,
                         void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* btn = new QPushButton(QString::fromUtf8(label), parent);
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
