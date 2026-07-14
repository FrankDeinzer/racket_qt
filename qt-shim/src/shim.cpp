#include <QApplication>
#include <QMainWindow>
#include <QWidget>
#include <QPushButton>
#include <QCheckBox>
#include <QListWidget>
#include <QComboBox>
#include <QRadioButton>
#include <QButtonGroup>
#include <QBoxLayout>
#include <QVariant>
#include <QSlider>
#include <QTabBar>
#include <QSignalBlocker>
#include <QMenuBar>
#include <QMenu>
#include <QAction>
#include <QLabel>
#include <QFileDialog>
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
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <algorithm>

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
// File dialog result: ud, path (UTF-8 C string, NULL if the user canceled).
typedef void (*shim_file_dialog_cb_t)(void* ud, const char* path);

static int    s_argc = 0;
static char** s_argv = nullptr;
static QApplication* s_app = nullptr;

// Temporary diagnostics, gated by env PLT_QT_DEBUG (read once). Left in the
// code intentionally — QMenuBar layout instrumentation for the menu-bar work.
static bool plt_qt_debug()
{
    static int cached = -1;
    if (cached < 0) {
        const char* v = std::getenv("PLT_QT_DEBUG");
        cached = (v && v[0] && v[0] != '0') ? 1 : 0;
    }
    return cached != 0;
}

// Phase-3 measurement knob (docs/2026-07-11_prompt.md): lets the native
// Windows common-item dialog be tried against the same open()+pump path
// without touching the get-file/put-file contract. Off (Qt-own dialog) by
// default; not a supported/committed API switch, just a data point.
static bool plt_qt_native_file_dialog()
{
    static int cached = -1;
    if (cached < 0) {
        const char* v = std::getenv("PLT_QT_NATIVE_FILE_DIALOG");
        cached = (v && v[0] && v[0] != '0') ? 1 : 0;
    }
    return cached != 0;
}

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
    void paintEvent(QPaintEvent* e) override {
        QPainter p(this);
        if (!backing.isNull())
            p.drawImage(QRect(0, 0, width(), height()), backing);
        // Redraw-bug measurement (2026-07-09_prompt), discriminator 1: does
        // the OS-requested repaint region differ from what we actually blit
        // (always the full widget rect, regardless of e->rect())?
        if (plt_qt_debug() && e) {
            QRect r = e->rect();
            fprintf(stderr,
                    "[PLT_QT_DEBUG] paintEvent requested=(%d,%d %dx%d) "
                    "blitted=(0,0 %dx%d) backing=%dx%d\n",
                    r.x(), r.y(), r.width(), r.height(),
                    width(), height(), backing.width(), backing.height());
        }
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
    // Popup diagnostic: report when a popup (e.g. a menu dropdown) appears or
    // disappears, and its geometry, to distinguish never-shown vs shown-then-
    // closed vs off-screen. Transition-logged to avoid flooding every pump.
    if (plt_qt_debug()) {
        static QWidget* last = nullptr;
        QWidget* pop = QApplication::activePopupWidget();
        if (pop != last) {
            if (pop) {
                QRect g = pop->frameGeometry();
                fprintf(stderr,
                    "[PLT_QT_DEBUG] popup APPEARED class=%s visible=%d "
                    "frameGeom=(%d,%d %dx%d)\n",
                    pop->metaObject()->className(), (int)pop->isVisible(),
                    g.x(), g.y(), g.width(), g.height());
                if (QMenu* qm = qobject_cast<QMenu*>(pop)) {
                    const auto acts = qm->actions();
                    fprintf(stderr,
                        "[PLT_QT_DEBUG] popup actions().size()=%d\n",
                        (int)acts.size());
                    for (int i = 0; i < acts.size(); ++i)
                        fprintf(stderr,
                            "[PLT_QT_DEBUG] popup action[%d] text='%s' sep=%d menu=%d "
                            "enabled=%d checked=%d\n",
                            i, qUtf8Printable(acts[i]->text()),
                            (int)acts[i]->isSeparator(),
                            (int)(acts[i]->menu() != nullptr),
                            (int)acts[i]->isEnabled(),
                            (int)acts[i]->isChecked());
                }
            } else {
                fprintf(stderr, "[PLT_QT_DEBUG] popup GONE\n");
            }
            last = pop;
        }
    }
}

// Returns elapsed microseconds for a single processEvents call.
// Used for diagnostics only.
long long shim_pump_us(int max_ms)
{
    if (!s_app) return 0;
    auto t0 = std::chrono::steady_clock::now();
    s_app->processEvents(QEventLoop::AllEvents, max_ms);
    auto t1 = std::chrono::steady_clock::now();
    return std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count();
}

int shim_events_pending(void)
{
#ifdef _WIN32
    return (GetQueueStatus(QS_ALLINPUT) != 0) ? 1 : 0;
#else
    // On macOS/Linux, report no pending events so Racket's scheduler can
    // sleep between pump-thread wakeups instead of spinning.
    return 0;
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
    if (visible && plt_qt_debug()) {
        // menuBar() is safe here only because one was already set; it would
        // auto-create an empty bar otherwise.
        QMenuBar* mb = rw->menuBar();
        QRect cg = rw->centralWidget() ? rw->centralWidget()->geometry() : QRect();
        fprintf(stderr,
            "[PLT_QT_DEBUG] (c) after show: mb.height=%d mb.sizeHint.h=%d "
            "mb.visible=%d actions=%d central.geom=(%d,%d %dx%d)\n",
            mb->height(), mb->sizeHint().height(), (int)mb->isVisible(),
            (int)mb->actions().size(), cg.x(), cg.y(), cg.width(), cg.height());
        // W3 measurement (2026-07-08_prompt-2), discriminator 2: QMenuBar popups
        // often require an active window. One-shot print, not a loop change.
        QWidget* aw = QApplication::activeWindow();
        if (aw)
            fprintf(stderr,
                "[PLT_QT_DEBUG] (d) activeWindow=%s title='%s'\n",
                aw->metaObject()->className(),
                aw->windowTitle().toUtf8().constData());
        else
            fprintf(stderr, "[PLT_QT_DEBUG] (d) activeWindow=NULL\n");
        // The real discriminator: a bar item with empty text gets a 0x0 rect
        // (collapsing the whole bar to height 0), regardless of layout state.
        QList<QAction*> acts = mb->actions();
        for (int i = 0; i < acts.size(); ++i) {
            QAction* a = acts[i];
            fprintf(stderr,
                "[PLT_QT_DEBUG] (c) action[%d] text='%s' rect=(%d,%d %dx%d)\n",
                i, a->text().toUtf8().constData(),
                mb->actionGeometry(a).x(), mb->actionGeometry(a).y(),
                mb->actionGeometry(a).width(), mb->actionGeometry(a).height());
        }
    }
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

// Gives keyboard focus to a widget (called by editor-canvas% grab-caret).
void shim_widget_set_focus(void* widget)
{
    static_cast<QWidget*>(widget)->setFocus();
}

// QWidget::setEnabled() -- toolkit-level parent disable while a modal
// dialog is open, mirroring win32's EnableWindow(hwnd, on?) and gtk's
// gtk_widget_set_sensitive(). Qt disables the whole widget subtree (title
// bar interaction stays with the window manager; child controls stop
// receiving mouse/keyboard input), so this is called on a frame's own
// top-level handle, not per-child (docs/HACKING.md §18.3).
void shim_widget_set_enabled(void* widget, int enabled)
{
    static_cast<QWidget*>(widget)->setEnabled(enabled != 0);
}

// QWidget::setVisible() -- toggles the actual native widget's visibility.
// window%'s generic `show` method only tracked a Racket-side flag before
// this (docs/HACKING.md §21): single-mixin's active-child (framework/
// private/panel.rkt, used by both the real Preferences dialog's
// panel:single% and any other show-based "only one child visible" pattern)
// positions every child unconditionally and relies entirely on native
// show/hide to make the inactive ones disappear -- win32/gtk's window base
// classes already reflect real visibility here, this backend's did not.
void shim_widget_set_visible(void* widget, int visible)
{
    static_cast<QWidget*>(widget)->setVisible(visible != 0);
}

// Translates a point in widget-local coordinates to global screen coordinates
// (QWidget::mapToGlobal). Used by window%'s client-to-screen so popup-menu and
// context menus land at the true screen position instead of the raw local
// coordinates (previously a no-op — see CLAUDE.md flag). DPR is pinned to 1
// (QT_SCALE_FACTOR=1 in shim_app_init), so device-independent px are used
// consistently on both sides; no per-monitor scaling case here.
void shim_widget_client_to_screen(void* widget, int x, int y, int* out_x, int* out_y)
{
    QPoint g = static_cast<QWidget*>(widget)->mapToGlobal(QPoint(x, y));
    *out_x = g.x();
    *out_y = g.y();
}

// QWidget::sizeHint() -- the control's natural size, queried right after
// construction so item-based widgets (button%/message%/check-box%/list-box%)
// can seed window%'s w/h fields the same way win32/gtk controls already know
// their real size immediately after CreateWindowEx/gtk_widget_size_request
// (see docs/HACKING.md §18.2: without this, make-item%'s post-construction
// min-width/min-height seed always reads 0, and children stack on top of
// each other in a panel).
void shim_widget_get_size_hint(void* widget, int* out_w, int* out_h)
{
    QSize s = static_cast<QWidget*>(widget)->sizeHint();
    *out_w = s.width();
    *out_h = s.height();
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
    // Redraw-bug measurement (2026-07-09_prompt), discriminator 2: does the
    // backing QImage stay full-canvas-sized on every flush, or does it
    // shrink to a sub-region? Logs size + timing, one line per blit.
    if (plt_qt_debug()) {
        static auto t_start = std::chrono::steady_clock::now();
        long long ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - t_start).count();
        fprintf(stderr,
                "[PLT_QT_DEBUG] blit_argb t=%lldms new=%dx%d prev_backing=%dx%d\n",
                ms, w, h, c->backing.width(), c->backing.height());
    }
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

// ---- menu-bar ---------------------------------------------------------------

void* shim_menubar_create(void)
{
    QMenuBar* mb = new QMenuBar(nullptr);
    if (plt_qt_debug())
        fprintf(stderr,
            "[PLT_QT_DEBUG] (a) menubar_create: sizeHint.h=%d height=%d native=%d\n",
            mb->sizeHint().height(), mb->height(), (int)mb->isNativeMenuBar());
    return mb;
}

// Attaches an existing QMenuBar to a QMainWindow.
// QMainWindow takes ownership; do NOT delete the QMenuBar separately after this.
void shim_window_set_menubar(void* win, void* menubar)
{
    RacketWindow* rw = static_cast<RacketWindow*>(win);
    QMenuBar*     mb = static_cast<QMenuBar*>(menubar);
    rw->setMenuBar(mb);
    if (plt_qt_debug()) {
        QRect cg = rw->centralWidget() ? rw->centralWidget()->geometry() : QRect();
        QRect cr = rw->contentsRect();
        fprintf(stderr,
            "[PLT_QT_DEBUG] (b) set_menubar: mb.height=%d mb.sizeHint.h=%d mb.visible=%d "
            "actions=%d central.geom=(%d,%d %dx%d) contentsRect=(%d,%d %dx%d)\n",
            mb->height(), mb->sizeHint().height(), (int)mb->isVisible(),
            (int)mb->actions().size(),
            cg.x(), cg.y(), cg.width(), cg.height(),
            cr.x(), cr.y(), cr.width(), cr.height());
    }
}

// Returns the QAction* for the menu at position pos in the bar, or nullptr.
void shim_menubar_enable_at(void* menubar, int pos, int on)
{
    QMenuBar* mb = static_cast<QMenuBar*>(menubar);
    QList<QAction*> acts = mb->actions();
    if (pos >= 0 && pos < acts.size())
        acts[pos]->setEnabled(on != 0);
}

void shim_menubar_remove_at(void* menubar, int pos)
{
    QMenuBar* mb = static_cast<QMenuBar*>(menubar);
    QList<QAction*> acts = mb->actions();
    if (pos >= 0 && pos < acts.size())
        mb->removeAction(acts[pos]);
}

// ---- menu -------------------------------------------------------------------

void* shim_menu_create(const char* title)
{
    return new QMenu(QString::fromUtf8(title));
}

void shim_menubar_add_menu(void* menubar, void* menu)
{
    static_cast<QMenuBar*>(menubar)->addMenu(
        static_cast<QMenu*>(menu));
}

// Sets a menu's title. Needed for top-level bar menus: QMenuBar::addMenu(QMenu*)
// derives the bar item's text from the menu's title, so an empty title yields a
// zero-size (invisible) bar item. Submenus get their title via add_submenu.
void shim_menu_set_title(void* menu, const char* title)
{
    static_cast<QMenu*>(menu)->setTitle(QString::fromUtf8(title));
}

// Add a submenu at the end; returns the QAction* that represents it.
void* shim_menu_add_submenu(void* menu, const char* title, void* submenu)
{
    QMenu* m = static_cast<QMenu*>(menu);
    QMenu* sub = static_cast<QMenu*>(submenu);
    sub->setTitle(QString::fromUtf8(title));
    return m->addMenu(sub);
}

void* shim_menu_add_separator(void* menu)
{
    return static_cast<QMenu*>(menu)->addSeparator();
}

void shim_menu_remove_action(void* menu, void* action)
{
    static_cast<QMenu*>(menu)->removeAction(
        static_cast<QAction*>(action));
}

// Gated, on-demand dump of a QMenu's actions().size() and per-action state.
// Unlike the popup-transition diagnostic in shim_pump, this fires every call
// regardless of popup visibility -- needed to observe enable/check/delete
// dispatch on a menu that stays open across mutations (2026-07-08_prompt-3).
void shim_menu_debug_dump(void* menu)
{
    if (!plt_qt_debug()) return;
    QMenu* m = static_cast<QMenu*>(menu);
    const auto acts = m->actions();
    fprintf(stderr, "[PLT_QT_DEBUG] dump actions().size()=%d\n", (int)acts.size());
    for (int i = 0; i < acts.size(); ++i)
        fprintf(stderr,
            "[PLT_QT_DEBUG] dump action[%d] text='%s' sep=%d menu=%d "
            "enabled=%d checked=%d\n",
            i, qUtf8Printable(acts[i]->text()),
            (int)acts[i]->isSeparator(),
            (int)(acts[i]->menu() != nullptr),
            (int)acts[i]->isEnabled(),
            (int)acts[i]->isChecked());
}

void shim_menu_popup(void* menu, int x, int y)
{
    static_cast<QMenu*>(menu)->popup(QPoint(x, y));
}

// ---- action -----------------------------------------------------------------

// Creates a leaf QAction and adds it to `menu`, mirroring shim_menu_add_submenu's
// addMenu() call. The action is parented to `menu` for lifetime (QMenu::addAction
// does NOT take ownership per Qt docs), so it is deleted when the menu is —
// consistent with removeAction() only detaching, never deleting.
void* shim_action_create(void* menu, const char* label, int checkable,
                         shim_callback_t cb, void* ud)
{
    QMenu* m = static_cast<QMenu*>(menu);
    auto* a = new QAction(QString::fromUtf8(label), m);
    a->setCheckable(checkable != 0);
    if (cb) {
        QObject::connect(a, &QAction::triggered,
                         [cb, ud](bool) { cb(ud); });
    }
    m->addAction(a);
    return a;
}

void shim_action_set_enabled(void* action, int on)
{
    static_cast<QAction*>(action)->setEnabled(on != 0);
}

void shim_action_set_label(void* action, const char* label)
{
    static_cast<QAction*>(action)->setText(QString::fromUtf8(label));
}

void shim_action_set_checked(void* action, int on)
{
    static_cast<QAction*>(action)->setChecked(on != 0);
}

int shim_action_is_checked(void* action)
{
    return static_cast<QAction*>(action)->isChecked() ? 1 : 0;
}

// ---- label (message%) -------------------------------------------------------

void* shim_label_create(void* parent_widget, const char* text)
{
    auto* lbl = new QLabel(QString::fromUtf8(text),
                           static_cast<QWidget*>(parent_widget));
    lbl->setWordWrap(false);
    return lbl;
}

void shim_label_set_text(void* label_ptr, const char* text)
{
    static_cast<QLabel*>(label_ptr)->setText(QString::fromUtf8(text));
}

// ---- check-box (check-box%) --------------------------------------------

void* shim_check_box_create(void*           parent_widget,
                            const char*     label,
                            shim_callback_t toggle_cb,
                            void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* cb = new QCheckBox(QString::fromUtf8(label), parent);
    if (toggle_cb) {
        QObject::connect(cb, &QCheckBox::toggled,
                         [toggle_cb, ud](bool) { toggle_cb(ud); });
    }
    return cb;
}

// Blocks the toggled signal so programmatic set-value calls (mirroring
// gtk/win32's no-clicked?/suppress-callback pattern) don't re-fire the
// Racket callback -- only genuine user clicks should.
void shim_check_box_set_checked(void* cb_ptr, int on)
{
    auto* cb = static_cast<QCheckBox*>(cb_ptr);
    QSignalBlocker blocker(cb);
    cb->setChecked(on != 0);
}

int shim_check_box_get_checked(void* cb_ptr)
{
    return static_cast<QCheckBox*>(cb_ptr)->isChecked() ? 1 : 0;
}

// ---- list-box (list-box%) -----------------------------------------------
// Single-column QListWidget only -- this backend's list-box% does not yet
// implement multi-column/report-mode lists (no driver needs it; see
// docs/HACKING.md's widget-addition checklist).

void* shim_list_box_create(void*           parent_widget,
                           int             kind, // 0=single 1=multiple 2=extended
                           shim_callback_t sel_cb,
                           void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* lb = new QListWidget(parent);
    QAbstractItemView::SelectionMode mode;
    switch (kind) {
        case 1:  mode = QAbstractItemView::MultiSelection;    break;
        case 2:  mode = QAbstractItemView::ExtendedSelection; break;
        default: mode = QAbstractItemView::SingleSelection;   break;
    }
    lb->setSelectionMode(mode);
    if (sel_cb) {
        QObject::connect(lb, &QListWidget::itemSelectionChanged,
                         [sel_cb, ud]() { sel_cb(ud); });
    }
    return lb;
}

void shim_list_box_clear(void* lb_ptr)
{
    static_cast<QListWidget*>(lb_ptr)->clear();
}

void shim_list_box_append(void* lb_ptr, const char* s)
{
    static_cast<QListWidget*>(lb_ptr)->addItem(QString::fromUtf8(s));
}

void shim_list_box_set_string(void* lb_ptr, int i, const char* s)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    if (auto* item = lb->item(i))
        item->setText(QString::fromUtf8(s));
}

void shim_list_box_delete(void* lb_ptr, int i)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    delete lb->takeItem(i);
}

int shim_list_box_count(void* lb_ptr)
{
    return static_cast<QListWidget*>(lb_ptr)->count();
}

int shim_list_box_is_selected(void* lb_ptr, int i)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    auto* item = lb->item(i);
    return (item && item->isSelected()) ? 1 : 0;
}

// Blocks itemSelectionChanged while applying a programmatic selection change
// (same rationale as shim_check_box_set_checked above).
void shim_list_box_select(void* lb_ptr, int i, int on)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    QSignalBlocker blocker(lb);
    if (auto* item = lb->item(i))
        item->setSelected(on != 0);
}

void shim_list_box_set_current(void* lb_ptr, int i)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    QSignalBlocker blocker(lb);
    lb->setCurrentRow(i);
}

int shim_list_box_selected_count(void* lb_ptr)
{
    return static_cast<QListWidget*>(lb_ptr)->selectedItems().size();
}

// Returns the row of the idx-th selected item in ascending row order
// (deterministic — QListWidget::selectedItems() order is unspecified),
// or -1 if idx is out of range.
int shim_list_box_selected_at(void* lb_ptr, int idx)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    QList<int> rows;
    for (auto* item : lb->selectedItems())
        rows.append(lb->row(item));
    std::sort(rows.begin(), rows.end());
    if (idx >= 0 && idx < rows.size())
        return rows[idx];
    return -1;
}

void shim_list_box_scroll_to(void* lb_ptr, int i)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    if (auto* item = lb->item(i))
        lb->scrollToItem(item);
}

// Best-effort approximations for list-box%'s wheel-scroll bookkeeping
// (get-first-item/number-of-visible-items) -- cosmetic scroll-step math only,
// not selection-affecting, so an approximation is acceptable here.
int shim_list_box_first_visible(void* lb_ptr)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    QModelIndex idx = lb->indexAt(QPoint(0, 0));
    return idx.isValid() ? idx.row() : 0;
}

int shim_list_box_visible_count(void* lb_ptr)
{
    auto* lb = static_cast<QListWidget*>(lb_ptr);
    if (lb->count() == 0) return 0;
    int rowH = lb->sizeHintForRow(0);
    if (rowH <= 0) return lb->count();
    int h = lb->viewport()->height();
    return (std::max)(1, h / rowH);
}

// ---- slider (slider%) -----------------------------------------------------

void* shim_slider_create(void*           parent_widget,
                         int             vertical, // 0=horizontal 1=vertical
                         int             lo,
                         int             hi,
                         int             init_value,
                         shim_callback_t changed_cb,
                         void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* sl = new QSlider(vertical ? Qt::Vertical : Qt::Horizontal, parent);
    sl->setRange(lo, hi);
    sl->setValue(init_value);
    if (changed_cb) {
        QObject::connect(sl, &QSlider::valueChanged,
                         [changed_cb, ud](int) { changed_cb(ud); });
    }
    return sl;
}

// Blocks valueChanged for programmatic set-value (same rationale as
// shim_check_box_set_checked above).
void shim_slider_set_value(void* sl_ptr, int v)
{
    auto* sl = static_cast<QSlider*>(sl_ptr);
    QSignalBlocker blocker(sl);
    sl->setValue(v);
}

int shim_slider_get_value(void* sl_ptr)
{
    return static_cast<QSlider*>(sl_ptr)->value();
}

// ---- choice (choice%) ------------------------------------------------------

void* shim_choice_create(void* parent_widget, shim_callback_t changed_cb, void* ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* cb = new QComboBox(parent);
    if (changed_cb) {
        QObject::connect(cb, &QComboBox::currentIndexChanged,
                         [changed_cb, ud](int) { changed_cb(ud); });
    }
    return cb;
}

// QComboBox emits currentIndexChanged when the first item is added
// (index -1 -> 0) and whenever clear()/removeItem() shifts the current
// index -- block for every programmatic mutation, not just set-selection.
void shim_choice_append(void* cb_ptr, const char* s)
{
    auto* cb = static_cast<QComboBox*>(cb_ptr);
    QSignalBlocker blocker(cb);
    cb->addItem(QString::fromUtf8(s));
}

void shim_choice_clear(void* cb_ptr)
{
    auto* cb = static_cast<QComboBox*>(cb_ptr);
    QSignalBlocker blocker(cb);
    cb->clear();
}

void shim_choice_delete(void* cb_ptr, int i)
{
    auto* cb = static_cast<QComboBox*>(cb_ptr);
    QSignalBlocker blocker(cb);
    cb->removeItem(i);
}

int shim_choice_count(void* cb_ptr)
{
    return static_cast<QComboBox*>(cb_ptr)->count();
}

void shim_choice_set_selection(void* cb_ptr, int i)
{
    auto* cb = static_cast<QComboBox*>(cb_ptr);
    QSignalBlocker blocker(cb);
    cb->setCurrentIndex(i);
}

int shim_choice_get_selection(void* cb_ptr)
{
    return static_cast<QComboBox*>(cb_ptr)->currentIndex();
}

// ---- radio-box (radio-box%) -------------------------------------------------
// QButtonGroup + QRadioButtons in a plain QWidget container with a vertical
// or horizontal QBoxLayout (mirrors gtk's gtk_vbox_new/gtk_hbox_new choice).
// A hidden, unaddressable "dummy" button shares the same exclusive
// QButtonGroup so set-selection(-1) can force every real button unchecked:
// QButtonGroup forbids unchecking the sole checked button by direct click,
// but checking a different (here invisible) member of the same group is
// allowed and reaches the same "none selected" state. Mirrors wx/gtk's
// radio-box.rkt dummy-button trick (gtk_radio_button_new sharing the group).
//
// The container QWidget* is the handle returned to Racket -- generic
// window% geometry code (shim_widget_set_geometry/get_size_hint) operates
// on it directly like any other widget. Per-instance state (button group,
// dummy, next id to assign) rides along as a QVariant<void*> property
// rather than a second handle, since window%'s `handle` field is shared,
// single-purpose plumbing.

static const int PLT_RADIO_DUMMY_ID = -1000;

struct PltRadioBox {
    QButtonGroup* group;
    QRadioButton* dummy;
    int           next_id;
};

static PltRadioBox* plt_radio_box_state(void* handle)
{
    auto* container = static_cast<QWidget*>(handle);
    return static_cast<PltRadioBox*>(container->property("plt_radio_box").value<void*>());
}

void* shim_radio_box_create(void* parent_widget, int horizontal,
                            shim_callback_t clicked_cb, void* ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* container = new QWidget(parent);
    QBoxLayout* layout = horizontal
        ? static_cast<QBoxLayout*>(new QHBoxLayout(container))
        : static_cast<QBoxLayout*>(new QVBoxLayout(container));
    (void)layout;

    auto* group = new QButtonGroup(container);
    auto* dummy = new QRadioButton(container);
    dummy->setVisible(false);
    group->addButton(dummy, PLT_RADIO_DUMMY_ID);

    if (clicked_cb) {
        QObject::connect(group, &QButtonGroup::idClicked,
                         [clicked_cb, ud](int) { clicked_cb(ud); });
    }

    auto* state = new PltRadioBox{group, dummy, 0};
    container->setProperty("plt_radio_box", QVariant::fromValue<void*>(state));
    return container;
}

void shim_radio_box_append_button(void* handle, const char* label)
{
    auto* container = static_cast<QWidget*>(handle);
    auto* state = plt_radio_box_state(handle);
    auto* btn = new QRadioButton(QString::fromUtf8(label), container);
    container->layout()->addWidget(btn);
    state->group->addButton(btn, state->next_id++);
}

// Blocks idClicked for programmatic selection changes (same rationale as
// shim_check_box_set_checked above) -- targets the group, since that's what
// the Racket-side callback is connected to, not the individual buttons.
void shim_radio_box_set_selection(void* handle, int i)
{
    auto* state = plt_radio_box_state(handle);
    QSignalBlocker blocker(state->group);
    if (i < 0) {
        state->dummy->setChecked(true);
    } else if (auto* btn = state->group->button(i)) {
        btn->setChecked(true);
    }
}

int shim_radio_box_get_selection(void* handle)
{
    auto* state = plt_radio_box_state(handle);
    int id = state->group->checkedId();
    return (id == PLT_RADIO_DUMMY_ID) ? -1 : id;
}

void shim_radio_box_enable_button(void* handle, int i, int on)
{
    auto* state = plt_radio_box_state(handle);
    if (auto* btn = state->group->button(i))
        btn->setEnabled(on != 0);
}

int shim_radio_box_button_focus(void* handle, int i)
{
    auto* state = plt_radio_box_state(handle);
    if (i == -1) {
        for (auto* btn : state->group->buttons()) {
            if (btn != state->dummy && btn->hasFocus())
                return state->group->id(btn);
        }
        return 0;
    }
    if (auto* btn = state->group->button(i))
        btn->setFocus();
    return i;
}

// ---- file dialog (get-file / put-file) -----------------------------------
// QFileDialog run non-modally: open() (window-modal to `parent`, returns to
// the caller immediately) instead of exec() -- no nested QEventLoop, so it
// integrates with shim_pump() the same way every other widget here does.
// The result comes back on QDialog::finished, which fires from inside a
// normal shim_pump() call; the Racket side turns that into a synchronous
// return via the same yield-on-semaphore mechanism as dialog% (docs/
// HACKING.md §16/§18.3). mode: 0 = open existing file, 1 = save.
void shim_file_dialog_create(void* parent_widget, int mode,
                             const char* caption, const char* directory,
                             const char* filename, const char* extension,
                             const char* filter,
                             shim_file_dialog_cb_t cb, void* ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* dlg = new QFileDialog(parent, QString::fromUtf8(caption));
    dlg->setOption(QFileDialog::DontUseNativeDialog,
                   !plt_qt_native_file_dialog());
    if (directory && directory[0])
        dlg->setDirectory(QString::fromUtf8(directory));
    if (filename && filename[0])
        dlg->selectFile(QString::fromUtf8(filename));
    if (extension && extension[0])
        dlg->setDefaultSuffix(QString::fromUtf8(extension));
    if (filter && filter[0])
        dlg->setNameFilter(QString::fromUtf8(filter));
    if (mode == 1) {
        dlg->setAcceptMode(QFileDialog::AcceptSave);
        dlg->setFileMode(QFileDialog::AnyFile);
    } else {
        dlg->setAcceptMode(QFileDialog::AcceptOpen);
        dlg->setFileMode(QFileDialog::ExistingFile);
    }

    QObject::connect(dlg, &QDialog::finished, [dlg, cb, ud](int result) {
        if (plt_qt_debug()) {
            fprintf(stderr, "[PLT_QT_DEBUG] file_dialog finished result=%d\n", result);
            fflush(stderr);
        }
        if (result == QDialog::Accepted) {
            QStringList sel = dlg->selectedFiles();
            if (plt_qt_debug()) {
                fprintf(stderr, "[PLT_QT_DEBUG] file_dialog selectedFiles.size=%d\n",
                        (int)sel.size());
                fflush(stderr);
            }
            if (!sel.isEmpty()) {
                QByteArray path = sel.first().toUtf8();
                if (plt_qt_debug()) {
                    fprintf(stderr, "[PLT_QT_DEBUG] file_dialog path='%s' calling cb=%p\n",
                            path.constData(), (void*)cb);
                    fflush(stderr);
                }
                if (cb) cb(ud, path.constData());
                if (plt_qt_debug()) {
                    fprintf(stderr, "[PLT_QT_DEBUG] file_dialog cb returned\n");
                    fflush(stderr);
                }
                dlg->deleteLater();
                if (plt_qt_debug()) {
                    fprintf(stderr, "[PLT_QT_DEBUG] file_dialog deleteLater done\n");
                    fflush(stderr);
                }
                return;
            }
        }
        if (cb) cb(ud, nullptr);
        dlg->deleteLater();
    });

    if (plt_qt_debug())
        fprintf(stderr,
                "[PLT_QT_DEBUG] file_dialog_create mode=%d native=%d dir='%s' "
                "file='%s' filter='%s'\n",
                mode, (int)plt_qt_native_file_dialog(),
                directory ? directory : "", filename ? filename : "",
                filter ? filter : "");

    dlg->open();
}

// ---- tab-panel (tab-panel%) ----------------------------------------------
// A QTabBar (native tab strip) + a plain QWidget content area, both siblings
// parented to a container QWidget -- NOT QTabWidget, which insists on owning
// one content page per tab. Both gtk's and win32's tab-panel.rkt keep
// exactly ONE wx-managed client area and let the native control supply only
// tab selection + a changed callback; the tab-panel's actual children are
// managed entirely by the shared mred/wx layer (Preferences swaps visible
// panels itself via panel:single%'s active-child), so a single shared
// content widget is the correct mirror of both oracles (docs/HACKING.md §21).
//
// Positioning of the tabbar/content is done explicitly by Racket (mirrors
// win32's MoveWindow-based tab-panel.rkt) via the existing generic
// shim_widget_set_geometry/shim_widget_get_size_hint calls on the widgets
// returned by the getters below -- deliberately NOT a QVBoxLayout, so
// get-client-size never has to guess whether a Qt layout has activated yet
// (a real risk for the very first layout pass before a dialog's initial
// show()).
//
// Per-instance state (tabbar + content widget) rides along as a
// QVariant<void*> property on the container, same convention as
// PltRadioBox above -- window%'s `handle` field stays single-purpose.

struct PltTabPanel {
    QTabBar* tabbar;
    QWidget* content;
};

static PltTabPanel* plt_tab_panel_state(void* handle)
{
    auto* container = static_cast<QWidget*>(handle);
    return static_cast<PltTabPanel*>(container->property("plt_tab_panel").value<void*>());
}

void* shim_tab_panel_create(void* parent_widget, shim_callback_t changed_cb, void* ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* container = new QWidget(parent);
    auto* tabbar = new QTabBar(container);
    auto* content = new QWidget(container);
    tabbar->show();
    content->show();

    if (changed_cb) {
        QObject::connect(tabbar, &QTabBar::currentChanged,
                         [changed_cb, ud](int idx) {
                             if (plt_qt_debug()) {
                                 fprintf(stderr, "[PLT_QT_DEBUG] tab_panel currentChanged idx=%d\n", idx);
                                 fflush(stderr);
                             }
                             changed_cb(ud);
                         });
    }

    if (plt_qt_debug()) {
        fprintf(stderr, "[PLT_QT_DEBUG] tab_panel_create container=%p tabbar=%p content=%p\n",
                (void*)container, (void*)tabbar, (void*)content);
        fflush(stderr);
    }

    auto* state = new PltTabPanel{tabbar, content};
    container->setProperty("plt_tab_panel", QVariant::fromValue<void*>(state));
    return container;
}

// Returns the QTabBar* -- Racket positions/queries it via the existing
// generic shim_widget_set_geometry/shim_widget_get_size_hint calls.
void* shim_tab_panel_get_tabbar_widget(void* handle)
{
    return plt_tab_panel_state(handle)->tabbar;
}

// Returns the QWidget* that tab-panel%'s children should use as their Qt
// parent (get-content-hwnd) -- same role as shim_window_get_content_widget.
void* shim_tab_panel_get_content_widget(void* handle)
{
    return plt_tab_panel_state(handle)->content;
}

// Blocks currentChanged for programmatic tab-list changes (same rationale as
// shim_check_box_set_checked/shim_radio_box_set_selection above) -- QTabBar
// auto-selects tab 0 when the first tab is added (index -1 -> 0), which must
// not reach the Racket callback.
void shim_tab_panel_append(void* handle, const char* label)
{
    auto* state = plt_tab_panel_state(handle);
    QSignalBlocker blocker(state->tabbar);
    state->tabbar->addTab(QString::fromUtf8(label));
}

void shim_tab_panel_delete(void* handle, int i)
{
    auto* state = plt_tab_panel_state(handle);
    QSignalBlocker blocker(state->tabbar);
    state->tabbar->removeTab(i);
}

void shim_tab_panel_set_label(void* handle, int i, const char* label)
{
    plt_tab_panel_state(handle)->tabbar->setTabText(i, QString::fromUtf8(label));
}

void shim_tab_panel_set_selection(void* handle, int i)
{
    auto* state = plt_tab_panel_state(handle);
    QSignalBlocker blocker(state->tabbar);
    state->tabbar->setCurrentIndex(i);
}

int shim_tab_panel_get_selection(void* handle)
{
    return plt_tab_panel_state(handle)->tabbar->currentIndex();
}

int shim_tab_panel_count(void* handle)
{
    return plt_tab_panel_state(handle)->tabbar->count();
}


} // extern "C"
