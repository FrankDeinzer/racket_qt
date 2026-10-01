#lang racket/gui
;; Block D backlog §2.6: combo-field% dropdown.  Click the arrow strip at the
;; right edge of the field; choosing an item must print "picked: <item>" and
;; put it into the field.  PLT_QT=1 for Qt, unset for the native comparison.
(define f (new frame% [label "combo-field-probe"] [width 360] [height 120]))
(define cf
  (new combo-field% [parent f] [label "Search:"]
       [choices '("alpha" "beta" "gamma")]
       [callback (lambda (c e) (printf "callback: ~s ~s\n" (send c get-value) (send e get-event-type)))]))
(void (new button% [parent f] [label "other focus target"]))
(send f show #t)
