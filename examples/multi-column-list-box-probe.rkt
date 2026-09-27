#lang racket/gui
; Probe for list-box%'s new multi-column tree path (§60.6): exercises the
; contract the Racket Package Manager (gui-pkg-manager-lib's by-list.rkt/
; by-installed.rkt) relies on -- multiple columns with headers,
; clickable-headers sorting via column-control-event%, set with several
; column lists at once, set-string on a specific column, real
; get-column-width/set-column-width values, and (since no installed package
; was found calling them) a from-scratch check that append-column/
; delete-column genuinely change the column count/data/width, not just a
; label.

(define frame (new frame% [label "multi-column list-box% Probe"] [width 900] [height 320]))
(define panel (new vertical-panel% [parent frame]))

(define status (new message% [parent panel] [label "no header click yet"] [stretchable-width #t]))

(define lb
  (new list-box%
       [label #f]
       [parent panel]
       [choices null]
       [columns '("Status" "Name" "Author" "Description")]
       [style '(multiple column-headers clickable-headers variable-columns)]
       [callback (lambda (lb e)
                   (cond
                     [(is-a? e column-control-event%)
                      (send status set-label (format "header clicked: column ~a" (send e get-column)))]
                     [else
                      (send status set-label (format "selection changed, selections=~a" (send lb get-selections)))]))]))

(send lb set
      '("*" "" "*" "")
      '("alpha-pkg" "beta-pkg" "gamma-pkg" "delta-pkg")
      '("alice" "bob" "carol" "dave")
      '("first package" "second package" "third package" "fourth package"))

(send lb set-string 1 "BETA-PKG (renamed)" 1)
(send lb set-column-width 0 30 2 1000)
(send lb set-column-width 3 300 2 1000)

(define-values (w0 mn0 mx0) (send lb get-column-width 0))
(define-values (w3 mn3 mx3) (send lb get-column-width 3))
(printf "column 0: width=~a min=~a max=~a\n" w0 mn0 mx0)
(printf "column 3: width=~a min=~a max=~a\n" w3 mn3 mx3)
(printf "column order (before append): ~a\n" (send lb get-column-order))
(printf "number of rows: ~a\n" (send lb get-number))

; ---- append-column: verify it's a REAL column, not just a label ----
; get-column-order reads back QHeaderView::logicalIndex(pos) for each visual
; position -- if Qt's column count didn't really grow, position 4 doesn't
; exist and this would either error or (depending on Qt's own bounds
; handling) not return 4 here.
(send lb append-column "Tags")
(send lb set-string 0 "misc" 4)
(send lb set-string 1 "urgent" 4)
(send lb set-column-width 4 120 2 1000)
(printf "after append-column: rows=~a, column order=~a\n"
        (send lb get-number) (send lb get-column-order))
(define-values (w4 mn4 mx4) (send lb get-column-width 4))
(printf "column 4 (new): width=~a min=~a max=~a\n" w4 mn4 mx4)

; Give every remaining column a DISTINCT explicit width so a width-shift
; bug (an earlier version of shim_list_tree_delete_column shifted cell/
; header TEXT left but not the on-screen section WIDTH) is unmistakable:
; if column 1 below reports 222 (Author's width) the fix works; 111
; (Name's old width) would mean the bug is back.
(send lb set-column-width 1 111 2 1000)
(send lb set-column-width 2 222 2 1000)
(send lb set-column-width 3 333 2 1000)
(printf "before delete, explicit widths: col1=111 col2=222 col3=333\n")

; ---- delete-column: remove column 1 ("Name") and verify the reflow ----
(send lb delete-column 1)
(printf "after delete-column 1: rows=~a, column order=~a\n"
        (send lb get-number) (send lb get-column-order))
(for ([i (in-range 4)])
  (define-values (w mn mx) (send lb get-column-width i))
  (printf "  column ~a: width=~a min=~a max=~a\n" i w mn mx))
; No public list-box% method reads back an arbitrary column's cell text
; (get-string only reads mred's own column-0 "content" list, see
; mritem.rkt:600) -- text reflow after delete-column is checked visually
; via the screenshot below instead.
(flush-output)

(send frame show #t)
