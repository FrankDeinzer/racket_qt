#include <QApplication>
#include <QGuiApplication>
#include <QWindow>
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
#include <QProgressBar>
#include <QTabBar>
#include <QGroupBox>
#include <QFrame>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QMenuBar>
#include <QTimer>
#include <QHash>
#include <QPointer>
#include <QMenu>
#include <QAction>
#include <QLabel>
#include <QStyle>
#include <QFileDialog>
#include <QListView>
#include <QTreeView>
#include <QTreeWidget>
#include <QHeaderView>
#include <QVector>
#include <QImage>
#include <QPainter>
#include <QPrinter>
#include <QPrintDialog>
#include <QPageSetupDialog>
#include <QPageSize>
#include <QPageLayout>
#include <QResizeEvent>
#include <QPaintEvent>
#include <QShowEvent>
#include <QCloseEvent>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QKeyEvent>
#include <QFocusEvent>
#include <QEnterEvent>
#include <QClipboard>
#include <QMimeData>
#include <QUrl>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFont>
#include <QFontInfo>
#include <QCursor>
#include <QPixmap>
#include <QString>
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <chrono>
#include <algorithm>

// canvas% 'gl (HACKING §78): own QOpenGLContext + QOffscreenSurface + FBOs,
// frames read back into RacketCanvas::backing.  Only when CMake found
// Qt6::OpenGL (RQT_HAVE_GL); otherwise the shim_gl_* exports below are stubs
// that report "no GL".  Included before the X11 headers on purpose (Xlib's
// None/Bool/Status macros vs. Qt's GL headers).
#ifdef RQT_HAVE_GL
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLFramebufferObject>
#include <QOffscreenSurface>
#include <QSurfaceFormat>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef __APPLE__
#include <ApplicationServices/ApplicationServices.h>
#endif

#ifdef __linux__
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
// X11/X.h #defines CursorShape to 0 (an XFontCursor constant), which clobbers
// Qt::CursorShape used later in this file (shim_cursor_create_standard).
// It's the only Qt/Xlib macro collision in this translation unit (checked).
#undef CursorShape
// Same for X.h's KeyPress/KeyRelease (QEvent::KeyPress is used below).
#undef KeyPress
#undef KeyRelease
// QNativeInterface::QX11Application -- gives wx/qt/gcwin.rkt (DrRacket's GC
// indicator, register-collecting-blit) the same Display* Qt itself uses, so
// a raw Xlib child window created on it shares X11's request ordering with
// the rest of the app instead of opening a second, independent connection
// (unlike shim_x11_display() below, which is deliberately separate and
// query-only).
#include <QtGui/qguiapplication_platform.h>
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
// Mouse wheel: dx/dy are Qt's angleDelta in eighths of a degree (one notch =
// 120), dy > 0 meaning "away from the user" = scroll up. Racket turns this
// into a key-event% with key-code 'wheel-up/'wheel-down/'wheel-left/
// 'wheel-right, which is how racket/gui delivers the wheel (see
// wxme/editor-canvas.rkt's on-char and wx/gtk/window.rkt's connect-scroll).
typedef void (*shim_wheel_cb_t)(void* ud, int dx, int dy, int mods);

// Reports a native top-level resize. Carries the new size so Racket needs no
// live geometry query: wx/qt/window.rkt's w/h cache is the source of truth
// once it is maintained from here, exactly like wx/gtk/window.rkt's save-w/
// save-h (see its remember-size).
typedef void (*shim_resize_cb_t)(void* ud, int w, int h);
// File drop: called once per dropped local file, UTF-8 path valid only during the call.
typedef void (*shim_drop_cb_t)(void* ud, const char* path);
// Navigation keys from native controls: Qt::Key (Escape / Return / Enter), mods.
typedef void (*shim_nav_key_cb_t)(void* ud, int key, int mods);
// File dialog result: ud, path (UTF-8 C string, NULL if the user canceled).
typedef void (*shim_file_dialog_cb_t)(void* ud, const char* path);
typedef void (*shim_printer_dialog_cb_t)(void* ud, int accepted);
// Column header click (QHeaderView::sectionClicked): ud, logical column
// index. Used only by the multi-column list-box% tree path (§60.6) --
// posts a column-control-event%, mirroring the plain selection-fn callback's
// discipline (queue only, never call back synchronously, Regel 2).
typedef void (*shim_header_click_cb_t)(void* ud, int column);

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

// Menu-bar focus round trip (Block D §1.2b).  A menu-bar click makes the
// QMenuBar grab keyboard focus (MenuBarFocusReason) and Qt does not hand it
// back when the menu is closed with Escape, so typing afterwards went nowhere
// until the user clicked into the canvas again.  gtk keeps focus in the widget
// throughout.  The canvas remembers itself when the bar takes focus, and a
// menu's aboutToHide restores it once no popup is left open.
static QPointer<QWidget> s_focus_before_menubar;
static bool              s_restoring_focus = false;

static void restore_focus_after_menu()
{
    QTimer::singleShot(0, [] {
        if (QApplication::activePopupWidget()) return;          // menu-to-menu hop
        QWidget* fw = QApplication::focusWidget();
        if (!s_focus_before_menubar) return;
        if (fw && !qobject_cast<QMenuBar*>(fw)) return;          // focus went elsewhere legitimately
        s_restoring_focus = true;
        s_focus_before_menubar->setFocus(Qt::OtherFocusReason);
        s_restoring_focus = false;
        s_focus_before_menubar = nullptr;
    });
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
    shim_wheel_cb_t wheel_cb  = nullptr;
    void*           wheel_ud  = nullptr;
    // canvas% 'gl: the RacketGL state object (shim_canvas_gl_create,
    // HACKING §78), a QObject child of this canvas; nullptr for raster canvases.
    QObject*        gl_state  = nullptr;

    // Tab / Shift+Tab must reach Racket as ordinary key events (editor
    // indentation; racket/gui's own handle-traverse-key decides whether to
    // move focus, docs/HACKING.md §12).  Left to Qt, the focus chain eats Tab
    // before keyPressEvent whenever any other widget is focusable -- i.e. in
    // every real DrRacket window (Block D, input matrix `tab-reindent`).
    bool focusNextPrevChild(bool next) override {
        if (key_cb) return false;
        return QWidget::focusNextPrevChild(next);
    }

    RacketCanvas(QWidget* parent, shim_callback_t cb, void* ud)
        : QWidget(parent), expose_cb(cb), expose_ud(ud)
    {
        setMinimumSize(1, 1);
        // ClickFocus, not StrongFocus: canvases stay out of Qt's Tab chain (gtk:
        // canvas% is not tab-focusable unless accept-tab-focus); Racket's own
        // traversal (gets-focus? = tab-focus) handles Tab from inside a canvas.
        setFocusPolicy(Qt::ClickFocus);
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
        if (plt_qt_debug())
            fprintf(stderr, "[PLT_QT_DEBUG] canvas %p mousePress pos=(%d,%d) size=%dx%d cb=%d\n",
                    (void*)this, (int)e->position().x(), (int)e->position().y(),
                    width(), height(), mouse_cb ? 1 : 0);
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

    // ---- wheel ----------------------------------------------------------

    // Without a handler the event would propagate to the parent widget, which
    // is why the wheel was inert over a canvas before this existed. Only
    // accept it when a callback is actually wired, so an unwired canvas keeps
    // the default propagation.
    void wheelEvent(QWheelEvent* e) override {
        if (wheel_cb) {
            QPoint d = e->angleDelta();
            wheel_cb(wheel_ud, d.x(), d.y(), encodeMods(e->modifiers()));
            e->accept();
        } else {
            QWidget::wheelEvent(e);
        }
    }

    // ---- keyboard -------------------------------------------------------

    // X11 hardware keycode, packed above the modifier bits (<< 8) so Racket can
    // look up the key's other shift levels (get-other-shift-key-code etc.)
    // without changing the callback's signature.  0 elsewhere.
    static int keyExtra(QKeyEvent* e) {
#ifdef __linux__
        return (int)((e->nativeScanCode() & 0xffff) << 8);
#else
        (void)e; return 0;
#endif
    }
    static void debugKey(const char* what, QKeyEvent* e) {
        if (!plt_qt_debug()) return;
        fprintf(stderr, "[PLT_QT_DEBUG] %s key=0x%x text=[", what, (unsigned)e->key());
        for (QChar c : e->text()) fprintf(stderr, "%x ", (unsigned)c.unicode());
        fprintf(stderr, "] mods=0x%x nativeVK=0x%x nativeScan=0x%x autorep=%d\n",
                (unsigned)e->modifiers().toInt(), (unsigned)e->nativeVirtualKey(),
                (unsigned)e->nativeScanCode(), (int)e->isAutoRepeat());
    }
    void keyPressEvent(QKeyEvent* e) override {
        debugKey("press", e);
        if (key_cb) {
            int tc = e->text().isEmpty() ? 0 : (int)e->text().at(0).unicode();
            key_cb(key_ud, 0, e->key(), tc, encodeMods(e->modifiers()) | keyExtra(e));
        }
    }
    void keyReleaseEvent(QKeyEvent* e) override {
        debugKey("release", e);
        if (key_cb) {
            int tc = e->text().isEmpty() ? 0 : (int)e->text().at(0).unicode();
            key_cb(key_ud, 1, e->key(), tc, encodeMods(e->modifiers()) | keyExtra(e));
        }
    }

    // ---- focus ----------------------------------------------------------

    void focusInEvent(QFocusEvent* e) override {
        QWidget::focusInEvent(e);
        if (plt_qt_debug()) fprintf(stderr, "[PLT_QT_DEBUG] focusIn reason=%d\n", (int)e->reason());
        // A popup (menu-bar dropdown, context menu, choice/combo list) taking
        // and returning focus is not a focus change as far as Racket is
        // concerned (gtk never reports it; Block D §1.2).  Skip both edges so
        // on-set-focus / on-kill-focus stay balanced.
        if (e->reason() == Qt::PopupFocusReason || s_restoring_focus) return;
        if (focus_cb) focus_cb(focus_ud, 1);
    }
    void focusOutEvent(QFocusEvent* e) override {
        QWidget::focusOutEvent(e);
        if (plt_qt_debug()) fprintf(stderr, "[PLT_QT_DEBUG] focusOut reason=%d\n", (int)e->reason());
        if (e->reason() == Qt::PopupFocusReason) return;
        if (e->reason() == Qt::MenuBarFocusReason) {   // bar grabbed focus: not a Racket focus change
            s_focus_before_menubar = this;
            return;
        }
        if (focus_cb) focus_cb(focus_ud, 0);
    }
};

// Escape / Return from native controls (Block D, free-test finding 4).  Only
// canvas% delivers key events to Racket; with focus on a list, check box,
// radio, slider, choice or button, Escape (dialog cancel) and Return (default
// button) never reached racket/gui's dialog traversal.  The filter forwards
// just those keys and never consumes them.  Return on a QPushButton is left to
// the button (autoDefault clicks *that* button, like gtk).
class NavKeyFilter : public QObject {
public:
    shim_nav_key_cb_t cb; void* ud;
    NavKeyFilter(QObject* parent, shim_nav_key_cb_t c, void* u) : QObject(parent), cb(c), ud(u) {}
    bool eventFilter(QObject* o, QEvent* ev) override {
        if (ev->type() == QEvent::KeyPress) {
            auto* ke = static_cast<QKeyEvent*>(ev);
            int k = ke->key();
            bool ret = (k == Qt::Key_Return || k == Qt::Key_Enter);
            // Ctrl+<printable> chords (dialog shortcuts such as Choose Language's Ctrl+D/R/T/O) must also
            // reach racket/gui's pre-on-char chain; with focus in a native control they were lost (§74.7).
            bool chord = (ke->modifiers() & Qt::ControlModifier) && k >= 0x20 && k <= 0x7e;
            if (k == Qt::Key_Escape || chord || (ret && !qobject_cast<QPushButton*>(o)))
                {
                    Qt::KeyboardModifiers m = ke->modifiers();
                    int bits = (m & Qt::ShiftModifier ? 1 : 0) | (m & Qt::ControlModifier ? 2 : 0)
                             | (m & Qt::AltModifier ? 4 : 0) | (m & Qt::MetaModifier ? 8 : 0);
                    cb(ud, k, bits);
                }
        }
        return false;
    }
};

// Focus in/out reporting for native controls (button, check box, choice, slider,
// list, radio box, tab panel).  Same reason filter as RacketCanvas: popup and
// menu-bar focus is not a Racket focus change.  Never consumes the event.
class FocusFilter : public QObject {
public:
    shim_focus_cb_t cb; void* ud;
    FocusFilter(QObject* parent, shim_focus_cb_t c, void* u) : QObject(parent), cb(c), ud(u) {}
    bool eventFilter(QObject*, QEvent* ev) override {
        // X11 headers #define FocusIn/FocusOut; QEvent::FocusIn = 8, FocusOut = 9.
        const int et = (int)ev->type();
        if (et == 8 || et == 9) {
            auto* fe = static_cast<QFocusEvent*>(ev);
            Qt::FocusReason r = fe->reason();
            if (r == Qt::PopupFocusReason || r == Qt::MenuBarFocusReason || s_restoring_focus)
                return false;
            cb(ud, et == 8 ? 1 : 0);
        }
        return false;
    }
};

// File drop on an arbitrary widget (canvas% 'accept-drop-files, HACKING §83.2): an event filter instead of a
// subclass hook, so it works for every RacketCanvas/native control.  Accepts only URL drags; every local
// file of a drop is reported through `cb` (Racket posts one on-drop-file event per file, Regel 2).
class DropFilter : public QObject {
public:
    shim_drop_cb_t cb; void* ud;
    DropFilter(QObject* parent, shim_drop_cb_t c, void* u) : QObject(parent), cb(c), ud(u) {}
    bool eventFilter(QObject*, QEvent* ev) override {
        switch (ev->type()) {
        case QEvent::DragEnter:
        case QEvent::DragMove: {
            auto* de = static_cast<QDropEvent*>(ev);
            if (de->mimeData()->hasUrls()) { de->acceptProposedAction(); return true; }
            return false;
        }
        case QEvent::Drop: {
            auto* de = static_cast<QDropEvent*>(ev);
            if (!de->mimeData()->hasUrls()) return false;
            for (const QUrl& u : de->mimeData()->urls()) {
                if (!u.isLocalFile()) continue;
                QByteArray b = u.toLocalFile().toUtf8();
                if (cb) cb(ud, b.constData());
            }
            de->acceptProposedAction();
            return true;
        }
        default: return false;
        }
    }
};

// Debug only (PLT_QT_DEBUG): who actually receives mouse presses.  Installed on
// the QApplication in shim_app_init.
class DebugMouseFilter : public QObject {
public:
    bool eventFilter(QObject* o, QEvent* ev) override {
        if (ev->type() == QEvent::MouseButtonPress) {
            auto* me = static_cast<QMouseEvent*>(ev);
            auto* w = qobject_cast<QWidget*>(o);
            fprintf(stderr, "[PLT_QT_DEBUG] press -> %s %p geom=(%d,%d %dx%d) local=(%d,%d) global=(%d,%d)\n",
                    o->metaObject()->className(), (void*)o,
                    w ? w->x() : -1, w ? w->y() : -1, w ? w->width() : -1, w ? w->height() : -1,
                    (int)me->position().x(), (int)me->position().y(),
                    (int)me->globalPosition().x(), (int)me->globalPosition().y());
        }
        return false;
    }
};

// ---- RacketWindow -------------------------------------------------------

class RacketWindow : public QMainWindow {
public:
    shim_callback_t  close_cb;
    void*            close_ud;
    // Wired after construction via shim_window_set_resize_cb, not through the
    // constructor: resizeEvent fires during construction/first show, before
    // Racket's frame% object exists. Leaving it null until the frame is ready
    // drops those early events instead of posting into a half-built object.
    shim_resize_cb_t resize_cb = nullptr;
    void*            resize_ud = nullptr;
    // Wired via shim_window_set_move_cb: frame position changed (user drag, WM placement, our own move).
    shim_resize_cb_t move_cb = nullptr;
    void*            move_ud = nullptr;
    // Wired via shim_window_set_drop_cb (drag-accept-files #t); null = not accepting.
    shim_drop_cb_t   drop_cb = nullptr;
    void*            drop_ud = nullptr;
    // Wired via shim_window_set_activate_cb: window activation (QEvent::ActivationChange).
    shim_focus_cb_t  activate_cb = nullptr;
    void*            activate_ud = nullptr;
    int              last_active = -1;

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

    // Position of the client area in screen coordinates (gtk_window_get_position semantics, and the
    // same origin shim_widget_set_geometry moves -- so get-x/move round-trip without drifting by the
    // title-bar height).  The callback only posts (Regel 2).  Mirrors gtk's configure-event -> on-move.
    // Window (de)activation, independent of any focusable child.  Reports only changes of
    // isActiveWindow(); the callback only posts (Regel 2).  Popups do not deactivate the window.
    void changeEvent(QEvent* e) override {
        QMainWindow::changeEvent(e);
        if (e->type() == QEvent::ActivationChange && activate_cb) {
            int a = isActiveWindow() ? 1 : 0;
            if (a != last_active) { last_active = a; activate_cb(activate_ud, a); }
        }
    }

    void moveEvent(QMoveEvent* e) override {
        QMainWindow::moveEvent(e);
        if (move_cb) move_cb(move_ud, geometry().x(), geometry().y());
    }

    // File drag & drop (window%::drag-accept-files, Block D §2.3).  Only local
    // files are offered; the callback just posts (Regel 2).
    void dragEnterEvent(QDragEnterEvent* e) override {
        if (drop_cb && e->mimeData()->hasUrls()) e->acceptProposedAction();
        else QMainWindow::dragEnterEvent(e);
    }
    void dropEvent(QDropEvent* e) override {
        if (!drop_cb || !e->mimeData()->hasUrls()) { QMainWindow::dropEvent(e); return; }
        for (const QUrl& u : e->mimeData()->urls()) {
            if (!u.isLocalFile()) continue;
            QByteArray b = u.toLocalFile().toUtf8();
            drop_cb(drop_ud, b.constData());
        }
        e->acceptProposedAction();
    }

    // Base implementation first (QMainWindow lays out its menu bar and central
    // widget here), then report. Pattern follows focusOutEvent, not closeEvent
    // -- the latter deliberately swallows its event, this one must not.
    void resizeEvent(QResizeEvent* e) override {
        QMainWindow::resizeEvent(e);
        if (resize_cb && e->size().width() > 0 && e->size().height() > 0)
            resize_cb(resize_ud, e->size().width(), e->size().height());
    }
};

// ---- lifecycle ----------------------------------------------------------

void shim_app_init(void)
{
    if (s_app) return;
    qputenv("QT_SCALE_FACTOR", "1");
    QApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
#ifdef __APPLE__
    // Qt's default on macOS is to swap Ctrl and Cmd in every QKeyEvent/
    // QMouseEvent/queryKeyboardModifiers() modifier mask (Qt::ControlModifier
    // <-> physical Cmd, Qt::MetaModifier <-> physical Ctrl), so that a
    // cross-platform Qt::CTRL shortcut "just works" as Cmd on the Mac. This
    // backend never uses Qt's own shortcut matching (menu accelerators are
    // handled entirely by wx/qt/key-map.rkt's raw-bit translation via
    // encodeMods()/QGuiApplication::queryKeyboardModifiers(), docs/HACKING.md
    // §49.5), which assumes the *unswapped*, literal mapping racket/gui's own
    // convention expects (get-meta-down => Cmd, get-control-down => literal
    // Ctrl on Mac) -- so Qt's swap only worked against us here, silently
    // breaking every Cmd-based menu shortcut (Cmd+C/V/A/...) and the menu's
    // visible shortcut-key hint. Must be set before QApplication is
    // constructed (Qt::ApplicationAttribute contract).
    QCoreApplication::setAttribute(Qt::AA_MacDontSwapCtrlAndMeta);
#endif
    static char prog[] = "racket";
    static char* argv_arr[] = { prog, nullptr };
    s_argc = 1;
    s_argv = argv_arr;
    s_app = new QApplication(s_argc, s_argv);
    if (plt_qt_debug()) s_app->installEventFilter(new DebugMouseFilter());
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

// frame% style flags that need native window flags; call before the first show.
// bit0 = 'no-caption (frameless), bit1 = 'float (tool window above its parent that
// never takes focus -- gtk uses a GTK_WINDOW_POPUP, DrRacket's tooltip frame is
// '(no-caption float no-resize-border)).
void shim_window_set_style_flags(void* win, int flags)
{
    auto* rw = static_cast<RacketWindow*>(win);
    Qt::WindowFlags f = rw->windowFlags();
    if (flags & 1) f |= Qt::FramelessWindowHint;
    if (flags & 2) {
        f |= Qt::Tool | Qt::WindowStaysOnTopHint | Qt::WindowDoesNotAcceptFocus;
        rw->setAttribute(Qt::WA_ShowWithoutActivating, true);
    }
    rw->setWindowFlags(f);
}

void shim_window_set_size(void* win, int w, int h)
{
    static_cast<RacketWindow*>(win)->resize(w, h);
}

// Wires the native resize notification. Called once per frame, after the
// Racket-side frame% is constructed.
void shim_window_set_resize_cb(void* win, shim_resize_cb_t cb, void* ud)
{
    auto* rw = static_cast<RacketWindow*>(win);
    rw->resize_cb = cb;
    rw->resize_ud = ud;
}

// Wires the native move notification (client-area position, screen coordinates).
void shim_window_set_move_cb(void* win, shim_resize_cb_t cb, void* ud)
{
    auto* rw = static_cast<RacketWindow*>(win);
    rw->move_cb = cb;
    rw->move_ud = ud;
}

// Wires window activation reporting (frame%/dialog% on-activate for windows without a
// focusable child).  Returns 1 so the caller knows the shim supports it.
int shim_window_set_activate_cb(void* win, shim_focus_cb_t cb, void* ud)
{
    auto* rw = static_cast<RacketWindow*>(win);
    rw->activate_cb = cb;
    rw->activate_ud = ud;
    return 1;
}

// Moves the mouse pointer to global screen coordinates (QCursor::setPos).  Works on X11/Windows/
// macOS; Wayland ignores it.  Returns 1.
int shim_cursor_set_pos(int x, int y)
{
    QCursor::setPos(x, y);
    return 1;
}

// Current client-area position (screen coordinates) -> out[0]=x, out[1]=y.  Returns 1.
int shim_window_get_pos(void* win, int* out)
{
    auto* rw = static_cast<RacketWindow*>(win);
    out[0] = rw->geometry().x();
    out[1] = rw->geometry().y();
    return 1;
}

// Installs the Escape/Return forwarder on a native control (see NavKeyFilter).
void shim_widget_set_nav_key_cb(void* w, shim_nav_key_cb_t cb, void* ud)
{
    auto* widget = static_cast<QWidget*>(w);
    widget->installEventFilter(new NavKeyFilter(widget, cb, ud));
}

// Installs focus in/out reporting on a native control and on its focusable
// descendants (radio buttons, tab bar).
void shim_widget_set_focus_cb(void* w, shim_focus_cb_t cb, void* ud)
{
    auto* widget = static_cast<QWidget*>(w);
    auto* f = new FocusFilter(widget, cb, ud);
    widget->installEventFilter(f);
    for (auto* c : widget->findChildren<QWidget*>())
        if (c->focusPolicy() != Qt::NoFocus) c->installEventFilter(f);
}

// Enables/disables accepting dropped files on a top-level window (cb null = off).
void shim_window_set_drop_cb(void* win, shim_drop_cb_t cb, void* ud)
{
    auto* rw = static_cast<RacketWindow*>(win);
    rw->drop_cb = cb;
    rw->drop_ud = ud;
    rw->setAcceptDrops(cb != nullptr);
}

// Enables/disables accepting dropped files on a child widget (canvas%): cb null = off.  One DropFilter per
// widget (child object "plt_drop_filter"); a top-level frame uses shim_window_set_drop_cb instead.
void shim_widget_set_drop_cb(void* w, shim_drop_cb_t cb, void* ud)
{
    auto* widget = static_cast<QWidget*>(w);
    if (auto* old = widget->findChild<QObject*>("plt_drop_filter", Qt::FindDirectChildrenOnly)) {
        widget->removeEventFilter(old);
        delete old;
    }
    widget->setAcceptDrops(cb != nullptr);
    if (cb) {
        auto* f = new DropFilter(widget, cb, ud);
        f->setObjectName("plt_drop_filter");
        widget->installEventFilter(f);
    }
}

// Window-manager size limits (frame% enforce-size).  max < 0 = unbounded.
void shim_window_set_size_limits(void* win, int min_w, int min_h, int max_w, int max_h)
{
    auto* rw = static_cast<RacketWindow*>(win);
    rw->setMinimumSize((std::max)(0, min_w), (std::max)(0, min_h));
    rw->setMaximumSize(max_w < 0 ? QWIDGETSIZE_MAX : max_w,
                       max_h < 0 ? QWIDGETSIZE_MAX : max_h);
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

// ---- window state (maximize/iconize/fullscreen) --------------------------
// docs/HACKING.md §26/§27: wx/qt/frame.rkt previously had no override for
// these at all (hardcoded #f/no-op base from window.rkt).
//
// Uses setWindowState() with explicit Qt::WindowStates bit manipulation,
// NOT the showMaximized()/showMinimized()/showFullScreen()/showNormal()
// convenience methods -- those also call setVisible(true) internally,
// which would force a not-yet-shown frame onto the screen the moment
// `maximize`/`iconize`/`fullscreen` is called (confirmed empirically: a
// frame%'s own is-shown? stayed #f, as expected from Racket-side
// bookkeeping alone, while the real HWND was visible on screen -- exactly
// the maximize-before-show flow mred/private/mrtop.rkt uses via
// position-for-initial-show). Toggling one bit and leaving the others
// alone also means `iconize #f` restores whatever state (e.g. maximized)
// was set before iconizing, instead of clobbering it back to plain
// windowed -- matching win32's SW_RESTORE-from-WINDOWPLACEMENT semantics
// (win32/frame.rkt:596-602) instead of diverging from it. Still simpler
// than win32's independent tracking (its `fullscreen`, win32/frame.rkt:
// 627-673, does manual GWL_STYLE manipulation orthogonal to real maximize/
// minimize) since Qt's three bits share one QWidget-native windowState().

void shim_window_maximize(void* win, int on)
{
    auto* rw = static_cast<RacketWindow*>(win);
    Qt::WindowStates st = rw->windowState();
    if (on) st |= Qt::WindowMaximized; else st &= ~Qt::WindowMaximized;
    rw->setWindowState(st);
}

int shim_window_is_maximized(void* win)
{
    return static_cast<RacketWindow*>(win)->isMaximized() ? 1 : 0;
}

void shim_window_iconize(void* win, int on)
{
    auto* rw = static_cast<RacketWindow*>(win);
    Qt::WindowStates st = rw->windowState();
    if (on) st |= Qt::WindowMinimized; else st &= ~Qt::WindowMinimized;
    rw->setWindowState(st);
}

int shim_window_is_iconized(void* win)
{
    return static_cast<RacketWindow*>(win)->isMinimized() ? 1 : 0;
}

void shim_window_fullscreen(void* win, int on)
{
    auto* rw = static_cast<RacketWindow*>(win);
    Qt::WindowStates st = rw->windowState();
    if (on) st |= Qt::WindowFullScreen; else st &= ~Qt::WindowFullScreen;
    rw->setWindowState(st);
}

int shim_window_is_fullscreen(void* win)
{
    return static_cast<RacketWindow*>(win)->isFullScreen() ? 1 : 0;
}

// ---- geometry -----------------------------------------------------------

// Sets absolute position and size of any child QWidget.
// Called by Racket's layout engine after it computes positions.
void shim_widget_set_geometry(void* widget, int x, int y, int w, int h)
{
    static_cast<QWidget*>(widget)->setGeometry(x, y, w, h);
}

// canvas% 'no-focus: the widget never takes keyboard focus (policy 0 = Qt::NoFocus).
void shim_widget_set_no_focus(void* widget)
{
    static_cast<QWidget*>(widget)->setFocusPolicy(Qt::NoFocus);
}

// canvas% mit accept-tab-focus (text-field%/combo-field%-Editor-Canvas): Teil der Qt-Tab-Kette
// (StrongFocus), sonst bleibt es bei RacketCanvas' ClickFocus.  Tab *aus* dem fokussierten Canvas
// geht weiter ueber Racket (focusNextPrevChild=false mit key_cb).  Sektion 82.
void shim_widget_set_tab_focus(void* widget, int on)
{
    static_cast<QWidget*>(widget)->setFocusPolicy(on ? Qt::StrongFocus : Qt::ClickFocus);
}

// Gives keyboard focus to a widget (called by editor-canvas% grab-caret).
void shim_widget_set_focus(void* widget)
{
    auto* w = static_cast<QWidget*>(widget);
    // Labelled controls (choice, slider, list box, ...) hand out a container
    // (QLabel/QWidget) as their handle; focus the first focusable descendant.
    if (w->focusPolicy() == Qt::NoFocus) {
        for (auto* c : w->findChildren<QWidget*>())
            if (c->focusPolicy() != Qt::NoFocus && c->isVisibleTo(w) && c->isEnabled()) { w = c; break; }
    }
    w->setFocus();
}

// QWidget::setEnabled() -- toolkit-level parent disable while a modal
// dialog is open, mirroring win32's EnableWindow(hwnd, on?) and gtk's
// gtk_widget_set_sensitive(). Qt disables the whole widget subtree (title
// bar interaction stays with the window manager; child controls stop
// receiving mouse/keyboard input), so this is called on a frame's own
// top-level handle, not per-child (docs/HACKING.md §18.3).
void shim_widget_set_enabled(void* widget, int enabled)
{
    auto* w = static_cast<QWidget*>(widget);
    // Modal dialogs disable their owner windows (frame% modal-enable).  Disabling a window drops its focus
    // widget, and a window that is disabled when the X11 activation arrives is never activated by Qt, so
    // after the dialog closed menu shortcuts (F5, Ctrl+S ...) and typing stayed dead until the next click
    // (gtk keeps the focus window).  Remember the focus widget on disable; on enable activate the window
    // and give the widget focus back once the dialog is gone (next pump cycle).  HACKING 74.7.
    static QHash<QWidget*, QPointer<QWidget>> s_modal_focus;
    const bool was = w->isEnabled();
    if (!enabled && was && w->isWindow()) {
        QWidget* fw = QApplication::focusWidget();
        if (fw && (fw == w || w->isAncestorOf(fw))) s_modal_focus[w] = fw;
        else s_modal_focus.remove(w);
    }
    w->setEnabled(enabled != 0);
    if (enabled && !was && w->isWindow()) {
        QPointer<QWidget> g(w);
        QPointer<QWidget> saved = s_modal_focus.value(w);
        s_modal_focus.remove(w);
        QTimer::singleShot(0, w, [g, saved]() {
            if (!g || !g->isVisible() || !g->isEnabled()) return;
            g->activateWindow();
            if (saved && saved->isVisible() && saved->isEnabled()) saved->setFocus(Qt::OtherFocusReason);
        });
    }
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

// subwindow<%> reparent (panel%'s adopt-child -> window%'s set-parent, §75.1): QWidget::setParent
// moves the child under another container widget.  setParent hides the widget, so the caller's
// desired visibility is re-applied; the position is kept (Racket re-places the child right after).
void shim_widget_reparent(void* widget, void* new_parent, int visible)
{
    auto* w = static_cast<QWidget*>(widget);
    w->setParent(static_cast<QWidget*>(new_parent));
    w->setVisible(visible != 0);
}

// frame%'s set-icon (§75.1).  `src` = tightly packed straight-alpha (A,R,G,B) bytes, w*h*4.
// add 0: replace the window icon by this image; 1: add this image as a further size of the
// current icon (gtk's gtk_window_set_icon_list with several sizes); w <= 0: clear the icon.
// Returns 1.
int shim_window_set_icon(void* win, const uint8_t* src, int w, int h, int add)
{
    auto* rw = static_cast<QWidget*>(win);
    if (w <= 0 || h <= 0 || !src) { rw->setWindowIcon(QIcon()); return 1; }
    QImage img(w, h, QImage::Format_ARGB32);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            dst_row[x] = (uint32_t(src_row[x * 4 + 0]) << 24) | (uint32_t(src_row[x * 4 + 1]) << 16)
                       | (uint32_t(src_row[x * 4 + 2]) <<  8) |  uint32_t(src_row[x * 4 + 3]);
        }
    }
    QIcon icon = add ? rw->windowIcon() : QIcon();
    icon.addPixmap(QPixmap::fromImage(img));
    rw->setWindowIcon(icon);
    return 1;
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

// ---- cursor ---------------------------------------------------------------
// wx/qt/platform.rkt's cursor-driver% names the shape by string (not a raw
// Qt::CursorShape int) so the enum mapping lives in one place, symbolically,
// instead of two backends agreeing on magic numbers (contrast gtk/cursor.rkt's
// own "ugly!"-flagged raw GDK_* constants).
void* shim_cursor_create_standard(const char* name)
{
    QString s = QString::fromUtf8(name);
    Qt::CursorShape shape = Qt::ArrowCursor;
    if      (s == "arrow")       shape = Qt::ArrowCursor;
    else if (s == "cross")       shape = Qt::CrossCursor;
    else if (s == "hand")        shape = Qt::PointingHandCursor;
    else if (s == "ibeam")       shape = Qt::IBeamCursor;
    else if (s == "watch")       shape = Qt::WaitCursor;
    else if (s == "blank")       shape = Qt::BlankCursor;
    else if (s == "size-n/s")    shape = Qt::SizeVerCursor;
    else if (s == "size-e/w")    shape = Qt::SizeHorCursor;
    else if (s == "size-ne/sw")  shape = Qt::SizeBDiagCursor;
    else if (s == "size-nw/se")  shape = Qt::SizeFDiagCursor;
    else if (s == "arrow+watch") shape = Qt::BusyCursor;
    return new QCursor(shape);
}

// Custom-image cursor (cursor-driver%'s set-image, and the 'bullseye standard
// shape Qt has no native equivalent for). `src` is exactly the byte layout
// bitmap%'s get-argb-pixels already produces (A,R,G,B per pixel, tightly
// packed, no stride padding) -- same convention as shim_canvas_blit_argb
// below, just without that function's cairo-surface stride parameter, since
// this buffer is never a cairo surface.
void* shim_cursor_create_from_argb(const uint8_t* src, int w, int h, int hot_x, int hot_y)
{
    QImage img(w, h, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * w * 4;
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
    return new QCursor(QPixmap::fromImage(img), hot_x, hot_y);
}

// QWidget::setCursor() copies the QCursor by value, so the heap-allocated
// QCursor from the two functions above is never freed here -- matching
// win32's un-freed HCURSOR/gtk's un-freed GdkCursor (docs/HACKING.md's
// "Shim bleibt minimal" -- neither existing backend tracks cursor lifetime,
// and cursor-driver% instances are cached forever by wx/common/cursor.rkt's
// `standards` hash, so this leaks at most once per distinct symbol/image).
void shim_widget_set_cursor(void* widget, void* cursor)
{
    static_cast<QWidget*>(widget)->setCursor(*static_cast<QCursor*>(cursor));
}

void shim_widget_unset_cursor(void* widget)
{
    static_cast<QWidget*>(widget)->unsetCursor();
}

// ---- input state (get-current-mouse-state) --------------------------------
// QCursor::pos() (global desktop position) and
// QGuiApplication::queryKeyboardModifiers() (a genuine synchronous hardware
// query per Qt's own docs, unlike keyboardModifiers()/mouseButtons(), which
// only reflect events the application has actually received) are portable
// across all three platforms. QGuiApplication::mouseButtons() looked like
// the equivalent for buttons but is NOT -- measured, not assumed: a
// synthetic click delivered while this process's window lacked focus never
// showed up in mouseButtons() at all, because it reflects the app's own
// event stream, not real hardware state. Mouse buttons and Caps Lock (which
// has no Qt-level query either way) therefore need a platform-specific
// hardware query everywhere: Windows uses GetAsyncKeyState (mirroring
// wx/win32/procs.rkt's own check, including the swapped-buttons handling via
// GetSystemMetrics(SM_SWAPBUTTON)), since this backend also runs on Windows;
// macOS uses CGEventSourceButtonState/CGEventSourceFlagsState, the same
// class of global HID-session query this comment's own mouseButtons()
// rejection was looking for, just from Core Graphics instead of Qt. macOS
// has no button-swap query to mirror -- the OS remaps primary/secondary
// lower in the stack, so kCGMouseButtonLeft already means "whichever button
// acts as primary", matching wx/cocoa/procs.rkt's own unconditional #x1/
// 'left (mred/private/wx/cocoa/procs.rkt:293-294, no swap check there
// either). Middle button and the Meta modifier are included even though
// win32's own backend omits them -- GetAsyncKeyState(VK_MBUTTON)/
// kCGMouseButtonCenter and Qt::MetaModifier are all genuinely available, so
// there is no reason to reproduce that gap here.
// `out_flags` bit layout is a private contract with wx/qt/platform.rkt's
// get-current-mouse-state, not a mirror of any Qt enum's bit values.
#ifdef __linux__
// Separate, lazily-opened connection from Qt's own QPA display -- we only
// ever issue read-only global pointer/keyboard queries here, independent of
// any window. Kept open for the process lifetime (same pattern as e.g.
// xdotool), not tied to shim_app_quit's QApplication teardown.
//
// Only under the xcb platform plugin: under Wayland an XWayland $DISPLAY may exist, but its
// pointer/keyboard state only tracks X clients' windows, i.e. is stale/wrong for our native
// Wayland windows (HACKING §77).  Returns null there; callers degrade (Qt-API fallback).
static bool shim_is_xcb()
{
    static const bool xcb = QGuiApplication::platformName() == QLatin1String("xcb");
    return xcb;
}
static Display* shim_x11_display()
{
    static Display* dpy = shim_is_xcb() ? XOpenDisplay(nullptr) : nullptr;
    return dpy;
}
#endif

#ifdef __linux__
// Keysym of an X11 hardware keycode at a shift level (0 = base, 1 = shift), group 0.
// 0 when unavailable.  Used to fill key-event%'s other-*-key-code fields.
int shim_key_keysym(int keycode, int level)
{
    Display* dpy = shim_x11_display();
    if (!dpy || keycode <= 0) return 0;
    return (int)XkbKeycodeToKeysym(dpy, (KeyCode)keycode, 0, level);
}
#else
int shim_key_keysym(int, int) { return 0; }
#endif

void shim_get_mouse_state(int* out_x, int* out_y, int* out_flags)
{
    QPoint p = QCursor::pos();
    *out_x = p.x();
    *out_y = p.y();

    int flags = 0;

    Qt::KeyboardModifiers mods = QGuiApplication::queryKeyboardModifiers();
    if (mods & Qt::ShiftModifier)   flags |= 0x08;
    if (mods & Qt::ControlModifier) flags |= 0x10;
    if (mods & Qt::AltModifier)     flags |= 0x20;
    if (mods & Qt::MetaModifier)    flags |= 0x40;

#ifdef _WIN32
    bool swapped = GetSystemMetrics(SM_SWAPBUTTON) != 0;
    if (GetAsyncKeyState(swapped ? VK_RBUTTON : VK_LBUTTON) < 0) flags |= 0x01;
    if (GetAsyncKeyState(VK_MBUTTON) < 0)                        flags |= 0x02;
    if (GetAsyncKeyState(swapped ? VK_LBUTTON : VK_RBUTTON) < 0) flags |= 0x04;
    if (GetAsyncKeyState(VK_CAPITAL) < 0)                        flags |= 0x80;
#elif defined(__APPLE__)
    if (CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft))
        flags |= 0x01;
    if (CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonCenter))
        flags |= 0x02;
    if (CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonRight))
        flags |= 0x04;
    CGEventFlags kb = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    if (kb & kCGEventFlagMaskAlphaShift) flags |= 0x80;
#elif defined(__linux__)
    if (Display* dpy = shim_x11_display()) {
        Window root = DefaultRootWindow(dpy);
        Window ret_root, ret_child;
        int root_x, root_y, win_x, win_y;
        unsigned int mask;
        if (XQueryPointer(dpy, root, &ret_root, &ret_child, &root_x, &root_y,
                           &win_x, &win_y, &mask)) {
            if (mask & Button1Mask) flags |= 0x01;
            if (mask & Button2Mask) flags |= 0x02;
            if (mask & Button3Mask) flags |= 0x04;
            // X11 assigns the Lock modifier to Caps Lock by default; the
            // same bit XQueryPointer already returns, no separate Xkb call.
            if (mask & LockMask)    flags |= 0x80;
        }
    } else {
        // Wayland (no global pointer query): Qt's own last-known button state.
        Qt::MouseButtons mb = QGuiApplication::mouseButtons();
        if (mb & Qt::LeftButton)   flags |= 0x01;
        if (mb & Qt::MiddleButton) flags |= 0x02;
        if (mb & Qt::RightButton)  flags |= 0x04;
    }
#endif

    *out_flags = flags;
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

void shim_canvas_set_wheel_cb(void* canvas_ptr, shim_wheel_cb_t cb, void* ud)
{
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    c->wheel_cb = cb;
    c->wheel_ud = ud;
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

// ---- canvas% 'gl (HACKING §78) -------------------------------------------
// The GL context is our own QOpenGLContext on a QOffscreenSurface, created
// right away (so gl-context<%> ok? is meaningful before the first show, as
// sgl's gl-frame.rkt expects) and never recreated by Qt (QOpenGLWidget drops
// and rebuilds its context on reparent/top-level recreation, which would lose
// the user's display lists and textures).  Racket draws synchronously between
// shim_gl_make_current/_done_current into our `back` FBO (depth/stencil,
// optional MSAA).  shim_gl_swap blits back -> `front` (resolving MSAA), reads
// `front` back and stores it as the canvas' QImage backing, which the normal
// RacketCanvas::paintEvent shows.  No Qt -> Racket callbacks (Regel 1/2), no
// change to how the top-level window is composited, input untouched.
// Measured on the way (§78.2): drawing straight into a QOpenGLWidget's FBO
// does not work -- Qt clears it on its own schedule with the user's clear colour.
#ifdef RQT_HAVE_GL
#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif
#ifndef GL_UNSIGNED_INT_8_8_8_8_REV
#define GL_UNSIGNED_INT_8_8_8_8_REV 0x8367
#endif
#ifndef GL_PACK_ROW_LENGTH
#define GL_PACK_ROW_LENGTH 0x0D02
#endif
#ifndef GL_PACK_SKIP_ROWS
#define GL_PACK_SKIP_ROWS 0x0D03
#endif
#ifndef GL_PACK_SKIP_PIXELS
#define GL_PACK_SKIP_PIXELS 0x0D04
#endif
#ifndef GL_PIXEL_PACK_BUFFER
#define GL_PIXEL_PACK_BUFFER 0x88EB
#endif
#ifndef GL_PIXEL_PACK_BUFFER_BINDING
#define GL_PIXEL_PACK_BUFFER_BINDING 0x88ED
#endif

class RacketGL : public QObject {
public:
    RacketCanvas*             canvas  = nullptr;
    QOpenGLContext*           ctx     = nullptr;   // child of this
    QOffscreenSurface*        surface = nullptr;   // child of this
    QOpenGLFramebufferObject* back    = nullptr;
    QOpenGLFramebufferObject* front   = nullptr;
    int want_depth = 0, want_stencil = 0, want_samples = 0;

    explicit RacketGL(RacketCanvas* c) : QObject(c), canvas(c) {}
    ~RacketGL() override {
        // Children (ctx, surface) are deleted after this body, so the
        // context is still alive here.
        if (ctx && surface && ctx->makeCurrent(surface)) {
            delete back;  back = nullptr;
            delete front; front = nullptr;
            ctx->doneCurrent();
        }
    }

    bool isCurrent() const { return QOpenGLContext::currentContext() == ctx; }

    QSize pixelSize() const {
        const qreal r = canvas->devicePixelRatioF();
        return QSize((std::max)(1, qRound(canvas->width() * r)),
                     (std::max)(1, qRound(canvas->height() * r)));
    }

    // Context must be current.  (Re)creates back/front when the canvas' pixel
    // size changed; fresh buffers start black and the viewport is set to the
    // full size (what a newly created native GL window starts with).
    bool ensureBuffers() {
        const QSize sz = pixelSize();
        if (back && front && back->size() == sz) return true;
        delete back;  back = nullptr;
        delete front; front = nullptr;
        QOpenGLFramebufferObjectFormat bf;
        bf.setAttachment((want_depth > 0 || want_stencil > 0)
                         ? QOpenGLFramebufferObject::CombinedDepthStencil
                         : QOpenGLFramebufferObject::NoAttachment);
        if (want_samples > 0) bf.setSamples(want_samples);
        back  = new QOpenGLFramebufferObject(sz, bf);
        front = new QOpenGLFramebufferObject(sz);
        if (!back->isValid() || !front->isValid()) {
            delete back;  back = nullptr;
            delete front; front = nullptr;
            return false;
        }
        QOpenGLFunctions* f = ctx->functions();
        GLfloat cc[4];
        f->glGetFloatv(GL_COLOR_CLEAR_VALUE, cc);
        const GLboolean scissor = f->glIsEnabled(GL_SCISSOR_TEST);
        f->glDisable(GL_SCISSOR_TEST);
        f->glClearColor(0, 0, 0, 1);
        front->bind();
        f->glClear(GL_COLOR_BUFFER_BIT);
        back->bind();
        f->glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        f->glClearColor(cc[0], cc[1], cc[2], cc[3]);
        if (scissor) f->glEnable(GL_SCISSOR_TEST);
        f->glViewport(0, 0, sz.width(), sz.height());
        return true;
    }

    // back -> front (resolves MSAA), then read front into the canvas backing.
    // Context must be current.  The user's scissor test and pixel-pack state
    // are restored afterwards; `back` is bound again.
    void present() {
        if (!back || !front) return;
        QOpenGLFunctions* f = ctx->functions();
        const GLboolean scissor = f->glIsEnabled(GL_SCISSOR_TEST);
        if (scissor) f->glDisable(GL_SCISSOR_TEST);
        QOpenGLFramebufferObject::blitFramebuffer(
            front, QRect(QPoint(0, 0), front->size()),
            back,  QRect(QPoint(0, 0), back->size()),
            GL_COLOR_BUFFER_BIT, GL_NEAREST);
        if (scissor) f->glEnable(GL_SCISSOR_TEST);

        GLint align = 4, rowlen = 0, skiprows = 0, skippix = 0, pbo = 0;
        f->glGetIntegerv(GL_PACK_ALIGNMENT, &align);
        f->glGetIntegerv(GL_PACK_ROW_LENGTH, &rowlen);
        f->glGetIntegerv(GL_PACK_SKIP_ROWS, &skiprows);
        f->glGetIntegerv(GL_PACK_SKIP_PIXELS, &skippix);
        f->glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pbo);
        f->glPixelStorei(GL_PACK_ALIGNMENT, 4);
        f->glPixelStorei(GL_PACK_ROW_LENGTH, 0);
        f->glPixelStorei(GL_PACK_SKIP_ROWS, 0);
        f->glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
        if (pbo) f->glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);

        const QSize sz = front->size();
        QImage raw(sz, QImage::Format_ARGB32);
        front->bind();
        // GL_BGRA + 8_8_8_8_REV = one uint32 0xAARRGGBB per pixel on any
        // endianness, i.e. QImage::Format_ARGB32's layout.
        f->glReadPixels(0, 0, sz.width(), sz.height(), GL_BGRA,
                        GL_UNSIGNED_INT_8_8_8_8_REV, raw.bits());

        f->glPixelStorei(GL_PACK_ALIGNMENT, align);
        f->glPixelStorei(GL_PACK_ROW_LENGTH, rowlen);
        f->glPixelStorei(GL_PACK_SKIP_ROWS, skiprows);
        f->glPixelStorei(GL_PACK_SKIP_PIXELS, skippix);
        if (pbo) f->glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)pbo);
        back->bind();

        // GL rows are bottom-up; the window is opaque (like a GLX window), so
        // alpha is forced to 255 while flipping.
        QImage img(sz, QImage::Format_ARGB32_Premultiplied);
        const int h = sz.height(), w = sz.width();
        for (int y = 0; y < h; y++) {
            const uint32_t* src = reinterpret_cast<const uint32_t*>(raw.constScanLine(h - 1 - y));
            uint32_t*       dst = reinterpret_cast<uint32_t*>(img.scanLine(y));
            for (int x = 0; x < w; x++) dst[x] = src[x] | 0xFF000000u;
        }
        img.setDevicePixelRatio(canvas->devicePixelRatioF());
        canvas->backing = img;
        canvas->update();
    }
};
#endif

// Creates the GL state for a canvas% with style 'gl.  Arguments mirror
// gl-config%: depth/stencil/multisample sizes, legacy? (compatibility
// profile, needed for glBegin & co., i.e. sgl), double-buffered? (single-
// buffered presentation is done on the Racket side: swap after each
// call-as-current).  Returns the GL handle, or NULL when this shim was built
// without Qt OpenGL support or no context could be created -- racket/gui then
// keeps a plain raster canvas and get-gl-context answers #f (as gtk does).
void* shim_canvas_gl_create(void* canvas_ptr, int depth, int stencil,
                            int samples, int legacy, int dbl)
{
#ifdef RQT_HAVE_GL
    (void)dbl;
    auto* c = static_cast<RacketCanvas*>(canvas_ptr);
    if (!c) return nullptr;
    if (c->gl_state) return c->gl_state;
    QSurfaceFormat fmt = QSurfaceFormat::defaultFormat();
    fmt.setRenderableType(QSurfaceFormat::OpenGL);
    if (legacy) {
        fmt.setProfile(QSurfaceFormat::CompatibilityProfile);
    } else {
        // gtk asks for the newest core profile it can get (>= 3.2); ask for
        // 3.2 core, which drivers satisfy with their newest compatible version.
        fmt.setVersion(3, 2);
        fmt.setProfile(QSurfaceFormat::CoreProfile);
    }
    auto* g = new RacketGL(c);
    g->want_depth   = depth;
    g->want_stencil = stencil;
    g->want_samples = samples;
    g->ctx = new QOpenGLContext(g);
    g->ctx->setFormat(fmt);
    if (!g->ctx->create()) { delete g; return nullptr; }
    g->surface = new QOffscreenSurface(nullptr, g);
    g->surface->setFormat(g->ctx->format());
    g->surface->create();
    if (!g->surface->isValid()) { delete g; return nullptr; }
    c->gl_state = g;
    return g;
#else
    (void)canvas_ptr; (void)depth; (void)stencil; (void)samples;
    (void)legacy; (void)dbl;
    return nullptr;
#endif
}

// 1 while the context is usable.
int shim_gl_is_valid(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    return (g && g->ctx && g->ctx->isValid()) ? 1 : 0;
#else
    (void)gl; return 0;
#endif
}

// Makes the context current with the `back` FBO bound.  0 = not possible.
int shim_gl_make_current(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    if (!g || !g->ctx || !g->ctx->makeCurrent(g->surface)) return 0;
    if (!g->ensureBuffers()) return 0;
    g->back->bind();
    return 1;
#else
    (void)gl; return 0;
#endif
}

void shim_gl_done_current(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    if (g && g->ctx && g->isCurrent()) g->ctx->doneCurrent();
#else
    (void)gl;
#endif
}

// gl-context<%> swap-buffers: present `back` in the canvas.  Works whether or
// not the context is current; a swap inside call-as-current leaves it current
// with `back` bound.
void shim_gl_swap(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    if (!g || !g->ctx) return;
    const bool was_current = g->isCurrent();
    if (!was_current && !g->ctx->makeCurrent(g->surface)) return;
    g->present();
    if (!was_current) g->ctx->doneCurrent();
#else
    (void)gl;
#endif
}

// Size of the GL drawing surface in device pixels (get-gl-client-size).
int shim_gl_pixel_width(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    return g ? g->pixelSize().width() : 0;
#else
    (void)gl; return 0;
#endif
}

int shim_gl_pixel_height(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    return g ? g->pixelSize().height() : 0;
#else
    (void)gl; return 0;
#endif
}

// gl-context<%> get-handle: the QOpenGLContext* (opaque to Racket).
void* shim_gl_get_handle(void* gl)
{
#ifdef RQT_HAVE_GL
    auto* g = static_cast<RacketGL*>(gl);
    return g ? static_cast<void*>(g->ctx) : nullptr;
#else
    (void)gl; return nullptr;
#endif
}

void shim_canvas_destroy(void* canvas_ptr)
{
    delete static_cast<RacketCanvas*>(canvas_ptr);
}

// ---- panel --------------------------------------------------------------

// Creates a plain container widget (a QFrame so a border can be turned on).
// Racket positions it via shim_widget_set_geometry; children of the panel
// parent themselves here. QFrame with the default NoFrame style renders
// identically to a bare QWidget, so border=0 callers are unaffected.
void* shim_panel_create(void* parent_widget, int border)
{
    auto* frame = new QFrame(static_cast<QWidget*>(parent_widget));
    if (border) frame->setFrameStyle(QFrame::Box | QFrame::Plain);
    // A child QWidget starts out at Qt's default 100x30 at (0,0).  A panel that
    // Racket never positions (empty / zero-sized, e.g. DrRacket's uncommon
    // panels) would stay that size, invisibly covering whatever lies top-left
    // and swallowing its clicks (free test 2026-09-30: file-name dropdown dead).
    frame->setGeometry(0, 0, 0, 0);
    return frame;
}

// ---- button -------------------------------------------------------------

// §71: Fusion pads every text push button to >= 80 px; gtk sizes by label
// (+ ~18 px).  In DrRacket's find bar that made Next/Prev/Show Replace wider
// than gtk, so the "0 Matches" message wrapped onto two lines.  Linux only:
// Windows/macOS keep their platform's conventional minimum button width.
class RacketButton : public QPushButton {
public:
    RacketButton(const QString& text, QWidget* parent) : QPushButton(text, parent) {}
    QSize sizeHint() const override
    {
        QSize hint = QPushButton::sizeHint();
#ifdef __linux__
        if (!text().isEmpty() && icon().isNull()) {
            int w = fontMetrics().horizontalAdvance(text()) + 20;
            if (w < hint.width()) hint.setWidth(w);
        }
#endif
        return hint;
    }
};

void* shim_button_create(void*           parent_widget,
                         const char*     label,
                         shim_callback_t click_cb,
                         void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* btn = new RacketButton(QString::fromUtf8(label), parent);
    // Return/Enter on a *focused* button clicks it (gtk does; Qt only does so
    // when autoDefault is set, which it defaults to false outside a QDialog).
    // Block D §2.2.
    btn->setAutoDefault(true);
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

void shim_button_set_label(void* btn_ptr, const char* label)
{
    static_cast<QPushButton*>(btn_ptr)->setText(QString::fromUtf8(label));
}

// button% with a bitmap label or (list bitmap string pos) (Macro Stepper navigation buttons,
// many DrRacket/framework buttons): QPushButton::setIcon.  `src` is tightly packed straight-alpha
// (A,R,G,B) bytes, w*h*4 (bitmap%'s get-argb-pixels with pre-mult? = #f).  right != 0: icon right
// of the text (RightToLeft layout direction); w <= 0 clears the icon.  Returns 1.
int shim_button_set_icon(void* btn_ptr, const uint8_t* src, int w, int h, int right)
{
    auto* b = static_cast<QPushButton*>(btn_ptr);
    if (w <= 0 || h <= 0 || !src) { b->setIcon(QIcon()); return 1; }
    QImage img(w, h, QImage::Format_ARGB32);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            dst_row[x] = (uint32_t(src_row[x * 4 + 0]) << 24) | (uint32_t(src_row[x * 4 + 1]) << 16)
                       | (uint32_t(src_row[x * 4 + 2]) <<  8) |  uint32_t(src_row[x * 4 + 3]);
        }
    }
    b->setIcon(QIcon(QPixmap::fromImage(img)));
    b->setIconSize(QSize(w, h));
    b->setLayoutDirection(right ? Qt::RightToLeft : Qt::LeftToRight);
    return 1;
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

// Subclasses QMenu only to carry an about-to-show callback (docs/HACKING.md
// §37) -- the Qt analog of win32's WM_INITMENU / gtk's GtkMenuItem "select"
// signal, both of which fire `on-menu-click` -> `on-demand` right before a
// menu becomes visible so item enable/check state is current. Elsewhere in
// this file a void* known to hold a RacketMenu* is freely static_cast to
// QMenu* (single, non-virtual inheritance, same established pattern as
// RacketWindow/QWidget*).
// aboutToHide fires whenever this QMenu closes -- both on a real selection
// and on a plain dismiss (click outside, Escape). It's the Qt analog of
// gtk's GtkMenu "deactivate" signal, used the same way on the Racket side
// (wx/qt/menu.rkt): to detect the "dismissed without selecting anything"
// case for a standalone popup-menu% (docs/HACKING.md §59's open item).
// Per Qt's own activateAction() (qmenu.cpp), the menu is hidden -- emitting
// aboutToHide -- *before* the chosen QAction::trigger() runs, i.e. before
// shim_action_create's own `triggered` callback fires. wx/qt/menu.rkt does
// not rely on that order, though: it defers the actual selected-vs-none
// decision to a later, queued Racket thunk (mirroring gtk's cancel-none-box
// pattern), which is robust regardless of which native signal fires first.
class RacketMenu : public QMenu {
public:
    shim_callback_t about_to_show_cb = nullptr;
    void* about_to_show_ud = nullptr;
    shim_callback_t about_to_hide_cb = nullptr;
    void* about_to_hide_ud = nullptr;

    explicit RacketMenu(const QString& title) : QMenu(title)
    {
        QObject::connect(this, &QMenu::aboutToShow, [this]() {
            if (about_to_show_cb) about_to_show_cb(about_to_show_ud);
        });
        QObject::connect(this, &QMenu::aboutToHide, [this]() {
            if (about_to_hide_cb) about_to_hide_cb(about_to_hide_ud);
        });
    }
};

void* shim_menu_create(const char* title)
{
    RacketMenu* m = new RacketMenu(QString::fromUtf8(title));
    QObject::connect(m, &QMenu::aboutToHide, m, [] { restore_focus_after_menu(); });
    return m;
}

// Wires the native about-to-show notification. Called once per menu% (top-level
// bar menu, submenu, or popup menu alike -- all share shim_menu_create), right
// after construction.
void shim_menu_set_about_to_show_cb(void* menu, shim_callback_t cb, void* ud)
{
    auto* rm = static_cast<RacketMenu*>(menu);
    rm->about_to_show_cb = cb;
    rm->about_to_show_ud = ud;
}

// Wires the native about-to-hide notification. Called once per menu%, same
// lifetime pattern as shim_menu_set_about_to_show_cb above (docs/HACKING.md
// §59).
void shim_menu_set_about_to_hide_cb(void* menu, shim_callback_t cb, void* ud)
{
    auto* rm = static_cast<RacketMenu*>(menu);
    rm->about_to_hide_cb = cb;
    rm->about_to_hide_ud = ud;
}

void shim_menubar_add_menu(void* menubar, void* menu)
{
    QAction* a = static_cast<QMenuBar*>(menubar)->addMenu(
        static_cast<QMenu*>(menu));
    // Opt out of Qt's macOS text-heuristic MenuRole detection (§22): without
    // this, a top-level bar action can be silently reclassified/relocated by
    // Qt's Cocoa integration based on its title text alone.
    a->setMenuRole(QAction::NoRole);
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
    QAction* a = m->addMenu(sub);
    a->setMenuRole(QAction::NoRole); // §22: opt out of macOS auto-role heuristic
    return a;
}

void* shim_menu_add_separator(void* menu)
{
    QAction* a = static_cast<QMenu*>(menu)->addSeparator();
    a->setMenuRole(QAction::NoRole); // §22: opt out of macOS auto-role heuristic
    return a;
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

// Screens (display-size / display-origin / display-count).  Index 0 = primary.  out[0..3] = x, y, w, h of
// the full screen geometry (logical pixels).  shim_screen_geometry returns 1 on success, 0 for a bad index.
int shim_screen_count()
{
    return (int)QGuiApplication::screens().size();
}

int shim_screen_geometry(int num, int* out)
{
    const QList<QScreen*> scr = QGuiApplication::screens();
    if (num < 0 || num >= scr.size()) return 0;
    const QRect g = scr[num]->geometry();
    out[0] = g.x(); out[1] = g.y(); out[2] = g.width(); out[3] = g.height();
    return 1;
}

// Screen-configuration changes (display-changed, HACKING §83.3): screen added/removed, primary screen changed,
// geometry (resolution/position/orientation) of any screen changed.  gtk reports monitors-changed/size-changed
// the same way.  The callback only posts (Regel 2).  availableGeometry (panel moves) is deliberately not wired:
// gtk's size-changed is about the screen size, and DrRacket re-places windows on it.
typedef void (*shim_display_cb_t)(void* ud);
static shim_display_cb_t s_display_cb = nullptr;
static void*             s_display_ud = nullptr;
static void display_fire() { if (s_display_cb) s_display_cb(s_display_ud); }
static void display_watch_screen(QScreen* sc)
{
    QObject::connect(sc, &QScreen::geometryChanged, sc, [](const QRect&) { display_fire(); });
}
void shim_display_set_changed_cb(shim_display_cb_t cb, void* ud)
{
    s_display_cb = cb; s_display_ud = ud;
    static bool wired = false;
    if (wired) return;
    wired = true;
    for (QScreen* sc : QGuiApplication::screens()) display_watch_screen(sc);
    QObject::connect(qApp, &QGuiApplication::screenAdded, qApp, [](QScreen* sc) { display_watch_screen(sc); display_fire(); });
    QObject::connect(qApp, &QGuiApplication::screenRemoved, qApp, [](QScreen*) { display_fire(); });
    QObject::connect(qApp, &QGuiApplication::primaryScreenChanged, qApp, [](QScreen*) { display_fire(); });
}

void shim_menu_popup(void* menu, int x, int y)
{
    auto* m = static_cast<QMenu*>(menu);
    // QMenu::popup() only keeps the menu inside the screen, not inside the
    // available (panel-free) area, so a menu opened near the bottom edge covered
    // the desktop panel.  gtk flips it above the click point; do the same
    // (sweep finding: DrRacket's language popup in the status bar).
    QScreen* scr = QGuiApplication::screenAt(QPoint(x, y));
    if (!scr) scr = QGuiApplication::primaryScreen();
    if (scr) {
        const QRect avail = scr->availableGeometry();
        const QSize sz = m->sizeHint();
        if (y + sz.height() > avail.bottom() + 1)
            y = (std::max)(avail.top(), y - sz.height());
        if (x + sz.width() > avail.right() + 1)
            x = (std::max)(avail.left(), avail.right() + 1 - sz.width());
    }
    // Wayland: a popup needs a transient parent (xdg_popup), otherwise Qt logs "Failed to
    // create grabbing popup" and the menu may not appear.  QMenu is created parentless, so
    // attach the active (or any visible) top-level window's QWindow.  No-op under X11/others.
    if (QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        QWidget* par = QApplication::activeWindow();
        if (!par) {
            for (QWidget* w : QApplication::topLevelWidgets())
                if (w != m && w->isVisible() && w->windowHandle()) { par = w; break; }
        }
        if (par && par->windowHandle()) {
            m->winId(); // force native window creation so windowHandle() exists
            if (m->windowHandle()) m->windowHandle()->setTransientParent(par->windowHandle());
        }
    }
    m->popup(QPoint(x, y));
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
    a->setMenuRole(QAction::NoRole); // §22: opt out of macOS auto-role heuristic
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

// message% with a symbol label ('caution/'stop/other = question/'app) shows a standard dialog icon
// (gtk: dialog-warning/-error/-question at 48 px), with a bitmap label the bitmap.  Both clear
// the text.  kind: 1 caution, 2 stop, other question.  Returns 1.
int shim_label_set_standard_icon(void* label_ptr, int kind)
{
    auto* lbl = static_cast<QLabel*>(label_ptr);
    QStyle::StandardPixmap sp = kind == 1 ? QStyle::SP_MessageBoxWarning
                              : kind == 2 ? QStyle::SP_MessageBoxCritical
                                          : QStyle::SP_MessageBoxQuestion;
    lbl->setText(QString());
    lbl->setPixmap(QApplication::style()->standardIcon(sp).pixmap(48, 48));
    return 1;
}

// Same with a straight-alpha (A,R,G,B) w*h*4 buffer (bitmap%'s get-argb-pixels, pre-mult? = #f).
int shim_label_set_pixmap(void* label_ptr, const uint8_t* src, int w, int h)
{
    auto* lbl = static_cast<QLabel*>(label_ptr);
    if (w <= 0 || h <= 0 || !src) { lbl->setPixmap(QPixmap()); return 1; }
    QImage img(w, h, QImage::Format_ARGB32);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            dst_row[x] = (uint32_t(src_row[x * 4 + 0]) << 24) | (uint32_t(src_row[x * 4 + 1]) << 16)
                       | (uint32_t(src_row[x * 4 + 2]) <<  8) |  uint32_t(src_row[x * 4 + 3]);
        }
    }
    lbl->setText(QString());
    lbl->setPixmap(QPixmap::fromImage(img));
    return 1;
}

// message%.set-color: foreground (WindowText) colour of a text label; use=0 restores the default
// palette (message% with colour #f).  Returns 1.
int shim_label_set_color(void* label_ptr, int use, int r, int g, int b, int a)
{
    auto* lbl = static_cast<QLabel*>(label_ptr);
    if (!use) { lbl->setPalette(QPalette()); return 1; }
    QPalette pal = lbl->palette();
    pal.setColor(QPalette::WindowText, QColor(r, g, b, a));
    lbl->setPalette(pal);
    return 1;
}

// Control font (message%/button%/check-box%/... `font` init argument; gtk: install-control-font).
// face may be NULL/empty (keep the application font's family); size is in points unless
// size_in_pixels; weight_bold/italic/underline are 0/1.  Works on any QWidget.  Returns 1.
int shim_widget_set_font(void* widget_ptr, const char* face, double size, int size_in_pixels,
                         int bold, int italic, int underline)
{
    auto* w = static_cast<QWidget*>(widget_ptr);
    if (!w) return 0;
    QFont f = w->font();
    if (face && *face) f.setFamily(QString::fromUtf8(face));
    if (size > 0) {
        if (size_in_pixels) f.setPixelSize((int)(size + 0.5));
        else                f.setPointSizeF(size);
    }
    f.setBold(bold != 0);
    f.setItalic(italic != 0);
    f.setUnderline(underline != 0);
    w->setFont(f);
    w->updateGeometry();
    return 1;
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

// QListWidget::sizeHint() grows with row count, without an upper bound --
// unlike gtk/win32's native list controls, which report a small constant
// preferred height and rely on the surrounding layout plus their own
// scrollbar for anything longer. wx/qt/window.rkt's
// seed-size-from-native-hint captures sizeHint() once, right after the
// list is populated, and that becomes the widget's minimum height for the
// rest of its life -- for a long list (e.g. DrRacket's "Choose Language"
// "Collection Paths" panel) that minimum can exceed the space its parent
// panel actually has, pushing sibling widgets (the Add/Remove buttons
// below it) out of view instead of the list gaining a scrollbar. Capping
// the hint at a handful of rows here reproduces the gtk/win32 behavior.
class RacketListWidget : public QListWidget {
public:
    explicit RacketListWidget(QWidget* parent) : QListWidget(parent) {}
    QSize sizeHint() const override
    {
        QSize hint = QListWidget::sizeHint();
        // QListWidget asks for 256 px; gtk's list-box% is ~180 px wide.  Four such
        // lists side by side (Preferences > Editing > Indenting) made the whole
        // dialog 1060 px wide instead of 752 (screenshot sweep).  The layout can
        // still stretch the widget; this only lowers the minimum.
        static const int kMaxHintWidth = 180;
        if (hint.width() > kMaxHintWidth) hint.setWidth(kMaxHintWidth);
        int rowH = sizeHintForRow(0);
        if (rowH > 0) {
            static const int kMaxVisibleRows = 6;
            int capped = rowH * kMaxVisibleRows + 2 * frameWidth();
            if (hint.height() > capped) hint.setHeight(capped);
        }
        return hint;
    }
};

void* shim_list_box_create(void*           parent_widget,
                           int             kind, // 0=single 1=multiple 2=extended
                           shim_callback_t sel_cb,
                           void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* lb = new RacketListWidget(parent);
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

// Double-click activation of a list-box% row (QListWidget or QTreeWidget) -> 'list-box-dclick.
// Return does NOT activate: gtk (measured, §73) sends Return on a selected row to the dialog's
// default button, which NavKeyFilter already forwards.  cb only posts an event (rule 2).
void shim_list_box_set_activate_cb(void* view_ptr, shim_callback_t cb, void* ud)
{
    auto* view = static_cast<QAbstractItemView*>(view_ptr);
    if (!cb) return;
    QObject::connect(view, &QAbstractItemView::doubleClicked,
                     [cb, ud](const QModelIndex& i) { if (i.isValid()) cb(ud); });
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

// ---- list-tree (list-box%'s multi-column path) ---------------------------
// §60.6: a completely separate class + export family from the single-column
// RacketListWidget/shim_list_box_* above -- those are byte-for-byte
// untouched. wx/qt/list-box.rkt's `tree?` dispatch picks this path only for
// >1 column or an explicit 'column-headers style (see its header comment).
//
// QHeaderView has no native per-column min/max width (only a single global
// QHeaderView::minimumSectionSize) -- RacketTreeWidget tracks its own so
// get-column-size's contract (real values, not gtk/win32-incompatible
// literals) can be honored, mirroring GtkTreeViewColumn's min/max semantics.

class RacketTreeWidget : public QTreeWidget {
public:
    explicit RacketTreeWidget(QWidget* parent) : QTreeWidget(parent) {}
    QSize sizeHint() const override
    {
        // Same 6-visible-row cap as RacketListWidget (§60.4) -- a long
        // Package Manager result list must not become the panel's permanent
        // minimum height either.  §71: seed-size-from-native-hint reads this
        // right after creation, when the tree is still empty (sizeHintForRow
        // = -1) -- the cap never applied and QTreeView's 256x192 default became
        // the permanent minimum (gtk: ~72x41).  Estimate a row from the font,
        // show header + 4 rows, and cap the width like RacketListWidget.
        QSize hint = QTreeWidget::sizeHint();
        static const int kMaxHintWidth = 180;
        if (hint.width() > kMaxHintWidth) hint.setWidth(kMaxHintWidth);
        int rowH = sizeHintForRow(0);
        int rows = 6;
        if (rowH <= 0) { rowH = fontMetrics().height() + 4; rows = 4; }
        int headH = header() && !header()->isHidden() ? header()->sizeHint().height() : 0;
        int capped = headH + rowH * rows + 2 * frameWidth();
        if (hint.height() > capped) hint.setHeight(capped);
        return hint;
    }
    QVector<int> colMinW;
    QVector<int> colMaxW;
};

void* shim_list_tree_create(void*           parent_widget,
                            int             kind, // 0=single 1=multiple 2=extended
                            int             ncols,
                            shim_callback_t sel_cb,
                            void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* tw = new RacketTreeWidget(parent);
    tw->setColumnCount(ncols);
    tw->setRootIsDecorated(false);   // flat list, never a real tree (no children)
    tw->setAllColumnsShowFocus(true);
    tw->setSortingEnabled(false);    // caller (e.g. by-list.rkt) sorts itself
    tw->colMinW.fill(0, ncols);
    tw->colMaxW.fill(10000, ncols);
    QAbstractItemView::SelectionMode mode;
    switch (kind) {
        case 1:  mode = QAbstractItemView::MultiSelection;    break;
        case 2:  mode = QAbstractItemView::ExtendedSelection; break;
        default: mode = QAbstractItemView::SingleSelection;   break;
    }
    tw->setSelectionMode(mode);
    if (sel_cb) {
        QObject::connect(tw, &QTreeWidget::itemSelectionChanged,
                         [sel_cb, ud]() { sel_cb(ud); });
    }
    return tw;
}

void shim_list_tree_set_headers_visible(void* tree_ptr, int visible)
{
    static_cast<QTreeWidget*>(tree_ptr)->setHeaderHidden(visible == 0);
}

void shim_list_tree_set_sections_movable(void* tree_ptr, int movable)
{
    static_cast<QTreeWidget*>(tree_ptr)->header()->setSectionsMovable(movable != 0);
}

void shim_list_tree_set_header_clicked_cb(void* tree_ptr, shim_header_click_cb_t cb, void* ud)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    QHeaderView* header = tree->header();
    header->setSectionsClickable(true);
    QObject::connect(header, &QHeaderView::sectionClicked,
                     [cb, ud](int logicalIndex) { if (cb) cb(ud, logicalIndex); });
}

void shim_list_tree_set_column_label(void* tree_ptr, int col, const char* label)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    if (auto* hdr = tree->headerItem())
        hdr->setText(col, QString::fromUtf8(label));
}

void shim_list_tree_set_column_width(void* tree_ptr, int col, int w, int mn, int mx)
{
    auto* tree = static_cast<RacketTreeWidget*>(tree_ptr);
    if (col < 0 || col >= tree->colMinW.size()) return;
    tree->colMinW[col] = mn;
    tree->colMaxW[col] = mx;
    int clamped = w;
    if (clamped < mn) clamped = mn;
    if (clamped > mx) clamped = mx;
    tree->header()->resizeSection(col, clamped);
}

void shim_list_tree_get_column_width(void* tree_ptr, int col, int* out_w, int* out_mn, int* out_mx)
{
    auto* tree = static_cast<RacketTreeWidget*>(tree_ptr);
    *out_w  = tree->header()->sectionSize(col);
    *out_mn = (col >= 0 && col < tree->colMinW.size()) ? tree->colMinW[col] : 0;
    *out_mx = (col >= 0 && col < tree->colMaxW.size()) ? tree->colMaxW[col] : 10000;
}

// Moves the column with logical index `logical` to visual position `pos`.
// wx/qt/list-box.rkt's set-column-order calls this once per position, from
// pos=0 upward -- same incremental algorithm as wx/gtk's
// gtk_tree_view_move_column_after loop in its own set-column-order.
void shim_list_tree_move_column(void* tree_ptr, int logical, int pos)
{
    auto* header = static_cast<QTreeWidget*>(tree_ptr)->header();
    int cur = header->visualIndex(logical);
    if (cur >= 0) header->moveSection(cur, pos);
}

int shim_list_tree_column_at_visual_pos(void* tree_ptr, int pos)
{
    return static_cast<QTreeWidget*>(tree_ptr)->header()->logicalIndex(pos);
}

void shim_list_tree_append_row(void* tree_ptr, const char* col0_text)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    auto* item = new QTreeWidgetItem(tree);
    item->setText(0, QString::fromUtf8(col0_text));
    tree->addTopLevelItem(item);
}

void shim_list_tree_set_cell(void* tree_ptr, int row, int col, const char* text)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    if (auto* item = tree->topLevelItem(row))
        item->setText(col, QString::fromUtf8(text));
}

void shim_list_tree_clear(void* tree_ptr)
{
    static_cast<QTreeWidget*>(tree_ptr)->clear();
}

void shim_list_tree_delete_row(void* tree_ptr, int row)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    delete tree->takeTopLevelItem(row);
}

int shim_list_tree_count(void* tree_ptr)
{
    return static_cast<QTreeWidget*>(tree_ptr)->topLevelItemCount();
}

int shim_list_tree_is_selected(void* tree_ptr, int row)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    auto* item = tree->topLevelItem(row);
    return (item && item->isSelected()) ? 1 : 0;
}

void shim_list_tree_select(void* tree_ptr, int row, int on)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    QSignalBlocker blocker(tree);
    if (auto* item = tree->topLevelItem(row))
        item->setSelected(on != 0);
}

void shim_list_tree_set_current(void* tree_ptr, int row)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    QSignalBlocker blocker(tree);
    if (auto* item = tree->topLevelItem(row))
        tree->setCurrentItem(item);
}

int shim_list_tree_selected_count(void* tree_ptr)
{
    return static_cast<QTreeWidget*>(tree_ptr)->selectedItems().size();
}

// Same determinism rationale as shim_list_box_selected_at: QTreeWidget's
// selectedItems() order is unspecified, so sort by row before indexing.
int shim_list_tree_selected_at(void* tree_ptr, int idx)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    QList<int> rows;
    for (auto* item : tree->selectedItems())
        rows.append(tree->indexOfTopLevelItem(item));
    std::sort(rows.begin(), rows.end());
    if (idx >= 0 && idx < rows.size())
        return rows[idx];
    return -1;
}

void shim_list_tree_scroll_to(void* tree_ptr, int row)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    if (auto* item = tree->topLevelItem(row))
        tree->scrollToItem(item);
}

int shim_list_tree_first_visible(void* tree_ptr)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    QModelIndex idx = tree->indexAt(QPoint(0, 0));
    return idx.isValid() ? idx.row() : 0;
}

int shim_list_tree_visible_count(void* tree_ptr)
{
    auto* tree = static_cast<QTreeWidget*>(tree_ptr);
    if (tree->topLevelItemCount() == 0) return 0;
    int rowH = tree->sizeHintForRow(0);
    if (rowH <= 0) return tree->topLevelItemCount();
    int h = tree->viewport()->height();
    return (std::max)(1, h / rowH);
}

// append-column/delete-column: no real caller found in any installed
// package (grep across /Applications/Racket v9.3/share/pkgs/, including
// gui-pkg-manager-lib/framework/drracket-core-lib -- only the public
// list-box%/type-stub/doc surface references them). Implemented anyway
// (real column-count change + data reflow, not a fake no-op) since the
// cost is low and the wx contract must not lie once it advertises a
// tree-backed multi-column widget.
void shim_list_tree_append_column(void* tree_ptr, const char* label)
{
    auto* tree = static_cast<RacketTreeWidget*>(tree_ptr);
    int newCol = tree->columnCount();
    tree->setColumnCount(newCol + 1);
    if (auto* hdr = tree->headerItem())
        hdr->setText(newCol, QString::fromUtf8(label));
    tree->colMinW.append(0);
    tree->colMaxW.append(10000);
}

void shim_list_tree_delete_column(void* tree_ptr, int col)
{
    auto* tree = static_cast<RacketTreeWidget*>(tree_ptr);
    int ncols = tree->columnCount();
    if (col < 0 || col >= ncols) return;
    // Capture each remaining column's current on-screen width before
    // reflowing -- QHeaderView::resizeSection is per logical index, and
    // setColumnCount(ncols - 1) below only drops the section state for the
    // removed slot, it does not shift the others (a first version of this
    // function forgot this and column c silently kept its OLD width after
    // inheriting c+1's label/data, i.e. width and content went out of sync).
    QHeaderView* header = tree->header();
    QVector<int> widths(ncols);
    for (int c = 0; c < ncols; ++c) widths[c] = header->sectionSize(c);
    for (int r = 0; r < tree->topLevelItemCount(); ++r) {
        auto* item = tree->topLevelItem(r);
        for (int c = col; c < ncols - 1; ++c)
            item->setText(c, item->text(c + 1));
    }
    if (auto* hdr = tree->headerItem()) {
        for (int c = col; c < ncols - 1; ++c)
            hdr->setText(c, hdr->text(c + 1));
    }
    for (int c = col; c < ncols - 1; ++c) {
        if (c + 1 < tree->colMinW.size()) tree->colMinW[c] = tree->colMinW[c + 1];
        if (c + 1 < tree->colMaxW.size()) tree->colMaxW[c] = tree->colMaxW[c + 1];
        widths[c] = widths[c + 1];
    }
    if (!tree->colMinW.isEmpty()) tree->colMinW.removeLast();
    if (!tree->colMaxW.isEmpty()) tree->colMaxW.removeLast();
    tree->setColumnCount(ncols - 1);
    for (int c = col; c < ncols - 1; ++c)
        header->resizeSection(c, widths[c]);
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

// ---- gauge (gauge%) -------------------------------------------------------
// QProgressBar's min/max/value are already plain integers matching wx
// gauge%'s 0..range contract directly -- unlike gtk_progress_bar's
// 0.0-1.0 fraction API, no unit conversion is needed on either side.
// Purely visual/non-interactive: no changed callback, and the percentage
// overlay QProgressBar shows by default is turned off since wx gauge% never
// displays one.
void* shim_gauge_create(void* parent_widget, int vertical, int range, int init_value)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* pb = new QProgressBar(parent);
    pb->setOrientation(vertical ? Qt::Vertical : Qt::Horizontal);
    pb->setTextVisible(false);
    pb->setRange(0, range);
    pb->setValue(init_value);
    return pb;
}

void shim_gauge_set_range(void* g_ptr, int range)
{
    static_cast<QProgressBar*>(g_ptr)->setRange(0, range);
}

int shim_gauge_get_range(void* g_ptr)
{
    return static_cast<QProgressBar*>(g_ptr)->maximum();
}

void shim_gauge_set_value(void* g_ptr, int v)
{
    static_cast<QProgressBar*>(g_ptr)->setValue(v);
}

int shim_gauge_get_value(void* g_ptr)
{
    return static_cast<QProgressBar*>(g_ptr)->value();
}

// ---- scrollbar (canvas% do-set-scrollbars / manual scroll API) -----------

void* shim_scrollbar_create(void*           parent_widget,
                            int             vertical, // 0=horizontal 1=vertical
                            shim_callback_t changed_cb,
                            void*           ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* sb = new QScrollBar(vertical ? Qt::Vertical : Qt::Horizontal, parent);
    if (changed_cb) {
        QObject::connect(sb, &QScrollBar::valueChanged,
                         [changed_cb, ud](int) { changed_cb(ud); });
    }
    return sb;
}

// Blocks valueChanged for programmatic range/value sets (same rationale as
// shim_slider_set_value above). `step` drives arrow-click/wheel granularity
// (QScrollBar::setSingleStep) -- wx's h-step/v-step init args.
void shim_scrollbar_set_range(void* sb_ptr, int max, int page, int step)
{
    auto* sb = static_cast<QScrollBar*>(sb_ptr);
    QSignalBlocker blocker(sb);
    sb->setRange(0, max);
    sb->setPageStep(page);
    sb->setSingleStep(step > 0 ? step : 1);
}

void shim_scrollbar_set_value(void* sb_ptr, int v)
{
    auto* sb = static_cast<QScrollBar*>(sb_ptr);
    QSignalBlocker blocker(sb);
    sb->setValue(v);
}

int shim_scrollbar_get_value(void* sb_ptr)
{
    return static_cast<QScrollBar*>(sb_ptr)->value();
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
    // §71: default layout margins/spacing (9/6 px under Fusion) made each radio row
    // ~28 px against gtk's ~23 and inflated dialogs with several radio-boxes
    // (Choose Language: 630 vs gtk 604 px; now ~600).  The container is a bare control substitute.
    // left 3: gtk keeps a few px between the item label and the radio indicator; QRadioButton
    // has none (label touched the indicator, visual matrix §84)
    layout->setContentsMargins(3, 4, 0, 4);
    layout->setSpacing(4);

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

// Swallows Key_Return/Key_Enter on a QFileDialog's internal list/tree views
// and calls QDialog::accept() instead of letting the event reach the view's
// own keyPressEvent (see the comment at its installation site below for why
// this is macOS-only).
#ifdef Q_OS_MACOS
class EnterAcceptsFilter : public QObject {
public:
    explicit EnterAcceptsFilter(QDialog* dlg) : QObject(dlg), m_dlg(dlg) {}
protected:
    bool eventFilter(QObject* watched, QEvent* event) override
    {
        if (event->type() == QEvent::KeyPress) {
            auto* ke = static_cast<QKeyEvent*>(event);
            if (ke->key() == Qt::Key_Return || ke->key() == Qt::Key_Enter) {
                m_dlg->accept();
                return true;
            }
        }
        return QObject::eventFilter(watched, event);
    }
private:
    QDialog* m_dlg;
};

static void install_enter_accepts_filter(QDialog* dlg)
{
    auto* filter = new EnterAcceptsFilter(dlg);
    for (auto* view : dlg->findChildren<QListView*>())
        view->installEventFilter(filter);
    for (auto* view : dlg->findChildren<QTreeView*>())
        view->installEventFilter(filter);
}
#endif

// ---- file dialog (get-file / put-file) -----------------------------------
// QFileDialog run non-modally: open() (window-modal to `parent`, returns to
// the caller immediately) instead of exec() -- no nested QEventLoop, so it
// integrates with shim_pump() the same way every other widget here does.
// The result comes back on QDialog::finished, which fires from inside a
// normal shim_pump() call; the Racket side turns that into a synchronous
// return via the same yield-on-semaphore mechanism as dialog% (docs/
// HACKING.md §16/§18.3). mode: 0 = open existing file, 1 = save.
// mode: 0 = open existing file, 1 = save, 2 = choose directory (get-directory), 3 = open several files
// (get-file-list; the callback gets the paths joined by '\n').  Modes 2/3 are only reachable through
// shim_file_dialog_create_ex (HACKING §83.1); the old export keeps its 0/1 contract.
static void file_dialog_create_impl(void* parent_widget, int mode,
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
    } else if (mode == 2) {
        dlg->setAcceptMode(QFileDialog::AcceptOpen);
        dlg->setFileMode(QFileDialog::Directory);
        dlg->setOption(QFileDialog::ShowDirsOnly, true);
    } else if (mode == 3) {
        dlg->setAcceptMode(QFileDialog::AcceptOpen);
        dlg->setFileMode(QFileDialog::ExistingFiles);
    } else {
        dlg->setAcceptMode(QFileDialog::AcceptOpen);
        dlg->setFileMode(QFileDialog::ExistingFile);
    }

    QObject::connect(dlg, &QDialog::finished, [dlg, cb, ud, mode](int result) {
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
                QByteArray path = (mode == 3 ? sel.join(QLatin1Char('\n')) : sel.first()).toUtf8();
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

    // Qt's own (non-native) file/tree view treats Return/Enter as one of its
    // EditKeyPressed triggers ONLY on macOS -- confirmed in Qt's own source
    // (qabstractitemview.cpp's keyPressEvent, #ifdef Q_OS_MACOS), where
    // pressing Enter on a selected file starts inline rename instead of
    // accepting the dialog (long-standing Qt/Cocoa convention, not something
    // wx/qt introduced -- native OS file pickers don't have this because
    // they don't use QAbstractItemView). On Windows/Linux, the #else branch
    // already does the right thing (emits `activated`, F2 is the only
    // rename key) -- installing this filter there would be redundant at
    // best, so it's scoped to macOS to avoid touching working behavior.
    // Blanket-disabling EditTriggers would also remove the F2-rename
    // convention users may expect from a native-feeling file list; instead,
    // install an event filter that intercepts only Key_Return/Key_Enter
    // *before* the view's own keyPressEvent (and its edit-trigger check)
    // sees it, and calls QFileDialog::accept() directly -- the same thing
    // the "Open" button does, which already contains the correct "it's a
    // directory, navigate into it instead" logic (qfiledialog.cpp's
    // accept(), AnyFile/Directory cases: `if (info.isDir()) { setDirectory
    // (...); return; }` before ever closing the dialog). F2 (and the view's
    // own "Rename" context-menu action) are untouched.
#ifdef Q_OS_MACOS
    install_enter_accepts_filter(dlg);
#endif

    if (plt_qt_debug())
        fprintf(stderr,
                "[PLT_QT_DEBUG] file_dialog_create mode=%d native=%d dir='%s' "
                "file='%s' filter='%s'\n",
                mode, (int)plt_qt_native_file_dialog(),
                directory ? directory : "", filename ? filename : "",
                filter ? filter : "");

    dlg->open();
}

void shim_file_dialog_create(void* parent_widget, int mode,
                             const char* caption, const char* directory,
                             const char* filename, const char* extension,
                             const char* filter,
                             shim_file_dialog_cb_t cb, void* ud)
{
    file_dialog_create_impl(parent_widget, mode == 1 ? 1 : 0, caption, directory, filename, extension, filter, cb, ud);
}

void shim_file_dialog_create_ex(void* parent_widget, int mode,
                                const char* caption, const char* directory,
                                const char* filename, const char* extension,
                                const char* filter,
                                shim_file_dialog_cb_t cb, void* ud)
{
    file_dialog_create_impl(parent_widget, mode, caption, directory, filename, extension, filter, cb, ud);
}

// ---- printer (printer-dc% / show-print-setup) ----------------------------
// Qt6 removed QPrinter::getDC() and there is no public path from a cairo_t*
// into QPainter, so wx/qt/printer-dc.rkt cannot reuse win32's
// cairo_win32_printing_surface_create(HDC) or gtk's native GtkPrintOperation
// cairo context. Instead, each recorded page is rasterized Racket-side into
// an ARGB32 cairo image surface and handed to shim_printer_draw_page as a
// raw premultiplied-ARGB32 buffer (same convention as shim_canvas_blit_argb),
// which wraps it in a QImage and draws it into the QPrinter's QPainter,
// stretched to fill the page -- text and vector art come out rasterized,
// not vector, on this backend only.
//
// QPrintDialog/QPageSetupDialog run non-modally (open() + finished), exactly
// like the QFileDialog above -- QDialog::exec() opens a nested QEventLoop,
// which CLAUDE.md Regel 1 forbids outright, native-dialog convenience or not.
void shim_printer_show_print_dialog(void* printer_ptr, void* parent_widget,
                                    shim_printer_dialog_cb_t cb, void* ud)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* dlg = new QPrintDialog(printer, parent);
    QObject::connect(dlg, &QDialog::finished, [dlg, cb, ud](int result) {
        if (cb) cb(ud, result == QDialog::Accepted ? 1 : 0);
        dlg->deleteLater();
    });
    dlg->open();
}

void shim_printer_show_page_setup_dialog(void* printer_ptr, void* parent_widget,
                                         shim_printer_dialog_cb_t cb, void* ud)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* dlg = new QPageSetupDialog(printer, parent);
    QObject::connect(dlg, &QDialog::finished, [dlg, cb, ud](int result) {
        if (cb) cb(ud, result == QDialog::Accepted ? 1 : 0);
        dlg->deleteLater();
    });
    dlg->open();
}

void* shim_printer_create(void)
{
    return new QPrinter();
}

void shim_printer_destroy(void* printer_ptr)
{
    delete static_cast<QPrinter*>(printer_ptr);
}

// paper_id: 1=A4 2=A3 3=Letter 4=Legal (mirrors ps-setup.rkt's paper-sizes
// order) -- the only four page sizes racket/draw's ps-setup% contract
// accepts, so no "unknown" case can arrive here.
static QPageSize::PageSizeId paper_id_to_qt(int paper_id)
{
    switch (paper_id) {
        case 2:  return QPageSize::A3;
        case 3:  return QPageSize::Letter;
        case 4:  return QPageSize::Legal;
        default: return QPageSize::A4;
    }
}

void shim_printer_set_page_setup(void* printer_ptr, int paper_id, int landscape)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    printer->setPageSize(QPageSize(paper_id_to_qt(paper_id)));
    printer->setPageOrientation(landscape ? QPageLayout::Landscape
                                          : QPageLayout::Portrait);
}

// Returns 0 (unrecognized paper -- caller keeps its previous paper-name) or
// 1..4 as above; *out_landscape is always meaningful.
int shim_printer_get_page_setup(void* printer_ptr, int* out_landscape)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    QPageLayout layout = printer->pageLayout();
    *out_landscape = (layout.orientation() == QPageLayout::Landscape) ? 1 : 0;
    switch (layout.pageSize().id()) {
        case QPageSize::A4:     return 1;
        case QPageSize::A3:     return 2;
        case QPageSize::Letter: return 3;
        case QPageSize::Legal:  return 4;
        default:                return 0;
    }
}

// Test-only escape hatch (examples/printer-probe.rkt, PLT_QT_PRINT_TO_PDF):
// redirects the job straight to a PDF file, bypassing QPrintDialog, so the
// probe can produce a durable, inspectable artifact without a real click.
void shim_printer_set_output_pdf(void* printer_ptr, const char* path)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    printer->setOutputFormat(QPrinter::PdfFormat);
    printer->setOutputFileName(QString::fromUtf8(path));
}

// Begins the print job (first page is implicitly ready once QPainter::begin
// returns); returns the QPainter* to pass to draw_page/new_page/end_job, or
// NULL if the printer/driver refused (e.g. output file not writable).
void* shim_printer_begin_job(void* printer_ptr, const char* doc_name)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    if (doc_name && doc_name[0])
        printer->setDocName(QString::fromUtf8(doc_name));
    auto* painter = new QPainter();
    if (!painter->begin(printer)) {
        delete painter;
        return nullptr;
    }
    return painter;
}

// argb_data: premultiplied ARGB32, w*h*stride bytes, same layout
// shim_canvas_blit_argb already assumes -- stretched to fill the printer's
// full printable-area rect, so the caller's raster resolution need not match
// the printer's native device resolution.
void shim_printer_draw_page(void* printer_ptr, void* painter_ptr,
                            const unsigned char* argb_data,
                            int w, int h, int stride)
{
    auto* printer = static_cast<QPrinter*>(printer_ptr);
    auto* painter = static_cast<QPainter*>(painter_ptr);
    QImage img(argb_data, w, h, stride, QImage::Format_ARGB32_Premultiplied);
    painter->drawImage(printer->pageRect(QPrinter::DevicePixel), img,
                       QRectF(0, 0, w, h));
}

int shim_printer_new_page(void* printer_ptr)
{
    return static_cast<QPrinter*>(printer_ptr)->newPage() ? 1 : 0;
}

void shim_printer_end_job(void* painter_ptr)
{
    auto* painter = static_cast<QPainter*>(painter_ptr);
    painter->end();
    delete painter;
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

// §71: content area of tab-panel% -- a plain QWidget plus a transparent
// 1-px frame overlay on top (gtk's notebook draws a border around the page;
// Qt had none because the content is not a QTabWidget).  The overlay sits above
// the children (they are parented to this widget by Racket) and ignores the mouse.
class RacketTabContent : public QWidget {
public:
    explicit RacketTabContent(QWidget* parent) : QWidget(parent)
    {
        overlay = new QFrame(this);
        overlay->setFrameShape(QFrame::StyledPanel);
        overlay->setFrameShadow(QFrame::Plain);
        overlay->setAttribute(Qt::WA_TransparentForMouseEvents);
        overlay->setFocusPolicy(Qt::NoFocus);
    }
protected:
    void resizeEvent(QResizeEvent* e) override
    {
        QWidget::resizeEvent(e);
        overlay->setGeometry(rect());
        overlay->raise();
        overlay->show();
    }
private:
    QFrame* overlay;
};

void* shim_tab_panel_create(void* parent_widget, shim_callback_t changed_cb, void* ud)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* container = new QWidget(parent);
    auto* tabbar = new QTabBar(container);
    tabbar->setFocusPolicy(Qt::StrongFocus); // Klick auf den Reiter fokussiert die Leiste (gtk), auch ohne Auswahlwechsel (§82)
    tabbar->setExpanding(false); // compact, left-aligned tabs like gtk (sweep finding)
    auto* content = new RacketTabContent(container);
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

// tab-panel% 'can-close / 'can-reorder (QTabBar::setTabsClosable / setMovable).
// close_cb(ud, index, 0): the user clicked a tab's [x] -- the tab is NOT
// removed here; Racket decides (on-choice-close) and calls delete.
// move_cb(ud, from, to): QTabBar already moved the tab after a mouse drag.
// Both only post (Regel 2).
void shim_tab_panel_set_options(void* handle, int closable, int movable,
                                shim_nav_key_cb_t close_cb, void* close_ud,
                                shim_nav_key_cb_t move_cb, void* move_ud)
{
    auto* tabbar = plt_tab_panel_state(handle)->tabbar;
    tabbar->setTabsClosable(closable != 0);
    tabbar->setMovable(movable != 0);
    if (closable && close_cb)
        QObject::connect(tabbar, &QTabBar::tabCloseRequested,
                         [close_cb, close_ud](int i) { close_cb(close_ud, i, 0); });
    if (movable && move_cb)
        QObject::connect(tabbar, &QTabBar::tabMoved,
                         [move_cb, move_ud](int from, int to) { move_cb(move_ud, from, to); });
}

int shim_tab_panel_count(void* handle)
{
    return plt_tab_panel_state(handle)->tabbar->count();
}

// ---- group-panel (group-panel%) ------------------------------------------
// A QGroupBox (native decorative frame + title) with a plain QWidget content
// area as its child -- mirrors tab-panel%'s tabbar+content split and win32/
// gtk's group-panel.rkt (native frame control, separate client area that
// children actually parent to). Unlike tab-panel%'s QTabBar, QGroupBox is
// already a QWidget container, so it doubles as the outer handle directly --
// no extra wrapper container widget needed.

struct PltGroupPanel {
    QGroupBox* box;
    QWidget* content;
};

static PltGroupPanel* plt_group_panel_state(void* handle)
{
    auto* box = static_cast<QGroupBox*>(handle);
    return static_cast<PltGroupPanel*>(box->property("plt_group_panel").value<void*>());
}

void* shim_group_panel_create(void* parent_widget, const char* label)
{
    auto* parent = static_cast<QWidget*>(parent_widget);
    auto* box = new QGroupBox(QString::fromUtf8(label), parent);
    auto* content = new QWidget(box);

    auto* state = new PltGroupPanel{box, content};
    box->setProperty("plt_group_panel", QVariant::fromValue<void*>(state));
    return box;
}

// Returns the QWidget* that group-panel%'s children should use as their Qt
// parent (get-content-hwnd) -- same role as shim_tab_panel_get_content_widget.
void* shim_group_panel_get_content_widget(void* handle)
{
    return plt_group_panel_state(handle)->content;
}

// QGroupBox::getContentsMargins() -- the space the native frame/title reserve
// around the content area; Racket uses this to position the content widget
// and to compute get-client-size (same "client delta" role as tab-panel%'s
// tab-height, docs/HACKING.md §21/§22).
void shim_group_panel_get_content_margins(void* handle, int* left, int* top, int* right, int* bottom)
{
    QMargins m = plt_group_panel_state(handle)->box->contentsMargins();
    *left = m.left();
    *top = m.top();
    *right = m.right();
    *bottom = m.bottom();
}

void shim_group_panel_set_label(void* handle, const char* label)
{
    plt_group_panel_state(handle)->box->setTitle(QString::fromUtf8(label));
}

// ---- clipboard ------------------------------------------------------------
// Text only (spike scope, docs/2026-09-14-4_report-linux.md "Nachtrag"):
// QClipboard is a plain synchronous global object, unlike gtk's async
// ownership-callback model -- clipboard-driver% (wx/qt/platform.rkt) writes
// through eagerly and reads back live, no C-to-Racket callback involved, so
// none of the #:atomic? rules (CLAUDE.md Regel 2) apply here.
//
// `mode` selects the QClipboard::Mode: 0 = QClipboard::Clipboard (the normal
// clipboard), 1 = QClipboard::Selection (X11's PRIMARY selection, used for
// middle-click paste; a no-op on platforms without selection support --
// see shim_clipboard_supports_selection below). Same three functions serve
// both the-clipboard and the-x-selection (wx/qt/platform.rkt's
// clipboard-driver%), not parallel duplicates.

static QClipboard::Mode shim_clipboard_qmode(int mode)
{
    return mode ? QClipboard::Selection : QClipboard::Clipboard;
}

void shim_clipboard_set_text(const char* utf8, int mode)
{
    QApplication::clipboard()->setText(QString::fromUtf8(utf8), shim_clipboard_qmode(mode));
}

// Returned pointer is only valid until the next shim_clipboard_* call --
// matches shim_version's convention (Racket's _string return type copies
// immediately during FFI marshaling, before this buffer can be reused).
const char* shim_clipboard_get_text(int mode)
{
    static QByteArray buf;
    buf = QApplication::clipboard()->text(shim_clipboard_qmode(mode)).toUtf8();
    return buf.constData();
}

int shim_clipboard_has_text(int mode)
{
    const QMimeData* md = QApplication::clipboard()->mimeData(shim_clipboard_qmode(mode));
    return (md && md->hasText()) ? 1 : 0;
}

// QClipboard::supportsSelection() -- true on X11 (always has a PRIMARY
// selection), false on Wayland/Windows/macOS depending on the platform
// plugin. Genuinely dynamic, unlike gtk's/win32's own hardcoded
// has-x-selection? values (gtk: always #t: X11-only backend; win32: always
// #f: no such concept) -- Qt is cross-platform, so it has to ask.
int shim_clipboard_supports_selection(void)
{
    return QApplication::clipboard()->supportsSelection() ? 1 : 0;
}

// ---- clipboard: bitmap (inventory item #13) --------------------------
// Always QClipboard::Clipboard -- unlike the text functions above, the
// bitmap clipboard has no Selection-mode consumer in wx/common/clipboard.rkt
// (only the-clipboard's get-clipboard-bitmap/set-clipboard-bitmap call these,
// never the-x-selection), so no mode parameter here.
//
// Byte convention: tightly packed (no stride padding), (A,R,G,B) per pixel --
// same as shim_cursor_create_from_argb/shim_canvas_blit_argb above, and the
// same convention racket/draw's bitmap%get-argb-pixels/set-argb-pixels use.
//
// shim_clipboard_set_image takes an already-premultiplied ARGB buffer (the
// Racket side calls get-argb-pixels with pre-mult?=#t, exactly like
// wx/qt/canvas.rkt's existing blit_argb caller) and unpacks it into a
// QImage::Format_ARGB32_Premultiplied the same way shim_cursor_create_from_argb
// does.
void shim_clipboard_set_image(const uint8_t* src, int w, int h)
{
    QImage img(w, h, QImage::Format_ARGB32_Premultiplied);
    for (int y = 0; y < h; y++) {
        auto*          dst_row = reinterpret_cast<uint32_t*>(img.scanLine(y));
        const uint8_t* src_row = src + (std::ptrdiff_t)y * w * 4;
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
    QApplication::clipboard()->setImage(img, QClipboard::Clipboard);
}

// hasImage() is a MIME-type check only, unlike image() which would force a
// (possibly expensive) format conversion just to answer a presence question.
int shim_clipboard_has_image(void)
{
    const QMimeData* md = QApplication::clipboard()->mimeData(QClipboard::Clipboard);
    return (md && md->hasImage()) ? 1 : 0;
}

// Two-step size-then-fill pattern (mirrors shim_group_panel_get_content_margins's
// multi-out-param style): lets the Racket side allocate the right-sized
// buffer before shim_clipboard_get_image_argb fills it. Returns 0 if the
// clipboard has no image (out params left untouched).
int shim_clipboard_image_size(int* out_w, int* out_h)
{
    if (!shim_clipboard_has_image()) return 0;
    QImage img = QApplication::clipboard()->image(QClipboard::Clipboard);
    if (img.isNull()) return 0;
    *out_w = img.width();
    *out_h = img.height();
    return 1;
}

// Converts to Format_ARGB32 (Qt's *non*-premultiplied 0xAARRGGBB layout --
// distinct from Format_ARGB32_Premultiplied used on the write side above) so
// Qt itself does the un-premultiplication, rather than this shim
// reimplementing that math by hand. Racket's set-argb-pixels is then called
// with its default pre-mult?=#f, matching this straight-alpha output.
//
// dst must already be sized (w*h*4 bytes) per a prior shim_clipboard_image_size
// call, and w/h are that same call's result -- the clipboard is a live
// external resource, so its content can change between the two calls (same
// caveat as native-text's read-back-live comment above); w/h let this
// function clamp its copy to the buffer Racket actually allocated instead of
// writing conv.width()*conv.height()*4 bytes of a possibly-larger new image
// into it (heap overflow otherwise). Any pixels beyond a shrunk clipboard
// image are left as zero (transparent black), matching bitmap%'s own
// out-of-range fill convention in do-get-argb-pixels.
void shim_clipboard_get_image_argb(uint8_t* dst, int w, int h)
{
    memset(dst, 0, (size_t)w * h * 4);
    QImage img = QApplication::clipboard()->image(QClipboard::Clipboard);
    if (img.isNull()) return;
    QImage conv = img.convertToFormat(QImage::Format_ARGB32);
    int copy_w = (std::min)(w, conv.width());
    int copy_h = (std::min)(h, conv.height());
    for (int y = 0; y < copy_h; y++) {
        const auto* src_row = reinterpret_cast<const uint32_t*>(conv.constScanLine(y));
        uint8_t*    dst_row = dst + (std::ptrdiff_t)y * w * 4;
        for (int x = 0; x < copy_w; x++) {
            uint32_t px = src_row[x];
            dst_row[x * 4 + 0] = (px >> 24) & 0xFF; // A
            dst_row[x * 4 + 1] = (px >> 16) & 0xFF; // R
            dst_row[x * 4 + 2] = (px >>  8) & 0xFF; // G
            dst_row[x * 4 + 3] =  px        & 0xFF; // B
        }
    }
}

// ---- control font -----------------------------------------------------
// QApplication::font() is Qt's default/control font (what freshly-created
// widgets inherit). QFontInfo resolves it against the actual font database,
// so the reported family is the real matched font (e.g. "Noto Sans" instead
// of a generic alias) -- mirrors gtk's approach of reading GtkSettings'
// already-resolved font name (docs/HACKING.md, Block C prompt 2026-09-22).

const char* shim_control_font_face(void)
{
    static QByteArray buf;
    QFontInfo info(QApplication::font());
    buf = info.family().toUtf8();
    return buf.constData();
}

// QFont can be set in either unit (setPointSize vs setPixelSize); when set
// in pixels, pointSize() returns -1 (and vice versa for pixelSize()) -- the
// unit actually in use must be read back, not assumed, or sizes come out
// off by the DPI ratio. *is_pixels reports which one shim_control_font_size
// returned.
int shim_control_font_size(int* is_pixels)
{
    QFontInfo info(QApplication::font());
    int pt = info.pointSize();
    if (pt > 0) {
        *is_pixels = 0;
        return pt;
    }
    *is_pixels = 1;
    return info.pixelSize();
}

// ---- bell ---------------------------------------------------------------
// gtk calls gdk_display_beep(); win32 calls MessageBeep(MB_OK). Qt's portable
// equivalent is QApplication::beep().

void shim_bell(void)
{
    QApplication::beep();
}

// ---- double-click time ---------------------------------------------------
// gtk reads the gtk-double-click-time GSetting; win32 hardcodes 500ms (no
// live query). Qt's equivalent is the static QApplication::doubleClickInterval()
// (ms), which reflects the platform theme setting.

int shim_double_click_time(void)
{
    return QApplication::doubleClickInterval();
}

// ---- gc indicator (register-collecting-blit / X11 raw-window support) ----
// wx/qt/gcwin.rkt (DrRacket's GC indicator, framework/private/frame.rkt's
// gc-canvas) ports wx/gtk/gcwin.rkt's design: at registration time it opens a
// small raw Xlib child window and, from then on, toggles its background
// pixmap through a Racket-runtime GC-callback opcode-vector that runs during
// a live GC pause -- so the toggle itself must never touch Qt, Racket, or the
// event loop (Regel 1/2). These two functions supply the only two pieces
// gtk got from GDK that Qt exposes differently: the X11 Display* connection
// Qt itself uses, and a widget's native X11 Window XID. Both are called only
// at registration/unregistration time (ordinary Racket context, not from
// inside the GC callback) -- see gcwin.rkt for the rest of the design and
// the GC-safety argument for what the callback itself calls (plain Xlib:
// XSetWindowBackgroundPixmap/XMapRaised/XUnmapWindow/XFlush).
#ifdef __linux__
// Null when Qt isn't running the xcb platform plugin (e.g. Wayland) -- the
// Racket side treats that as "unsupported here" and register-collecting-blit
// degrades to a no-op rather than crash (Regel 4).
void* shim_get_x11_display(void)
{
    if (auto* iface = qGuiApp->nativeInterface<QNativeInterface::QX11Application>())
        return iface->display();
    return nullptr;
}
#else
void* shim_get_x11_display(void) { return nullptr; }
#endif

// QWidget::winId() -- unlike GDK's gdk_x11_window_get_xid(gdk_window)
// indirection, this *is* the X11 Window XID directly on this platform, no
// separate lookup needed.
unsigned long shim_widget_get_x11_window(void* widget)
{
    return static_cast<unsigned long>(static_cast<QWidget*>(widget)->winId());
}

} // extern "C"
