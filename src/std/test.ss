;;; -*- Gerbil -*-
;;; (C) vyzo at hackzen.org
;;; Unit testing support
package: std

(import :gerbil/gambit
        :std/error
        :std/misc/list
        :std/sugar
        :std/format)
(export
  test-suite test-case
  check checkf
  check-eq? check-not-eq?
  check-eqv? check-not-eqv?
  check-equal? check-not-equal?
  check-output check-predicate check-exception
  !check-fail? !check-fail-e
  run-tests! test-report-summary!
  run-test-suite!
  test-result)

(defstruct !check-fail (e value loc))
(defstruct !check-error (exn check loc))
(defstruct !test-suite (desc thunk tests))
(defstruct !test-case (desc checks fail error))

(defmethod {display-exception !check-error}
  (lambda (self port)
    (with ((!check-error exn check loc) self)
      (fprintf port "~a at ~a: " check loc)
      (display-exception exn port))))

;; this is only necessary for stray checks outside a test-case
(defmethod {display-exception !check-fail}
  (lambda (self port)
    (with ((!check-fail check value loc) self)
      (fprintf port "check ~a at ~a FAILED: ~a~n"
               check loc value))))

(def *test-verbose* #t)

(def (set-test-verbose! val)
  (set! *test-verbose* val))

(def (verbose fmt . args)
  (when *test-verbose*
    (apply printf fmt args)))

(defrules test-suite ()
  ((_ desc body body-rest ...)
   (stx-string? #'desc)
   (make-test-suite desc (lambda () body body-rest ...))))

(defrules test-case ()
  ((_ desc body body-rest ...)
   (stx-string? #'desc)
   (run-test-case! desc (lambda () body body-rest ...))))

(defrules check (=> ?)
  ((_ expr => value)
   (check-equal? expr value))
  ((_ expr ? pred)
   (check-predicate expr (? pred)))
  ((_ eqf expr value)
   (checkf eqf expr value)))

(defrules print-check-e ()
  ((_ expr eqv value)
   (verbose "... check ~a is ~a to ~s~n" 'expr 'eqv value)))

(defrules checkf ()
  ((_ eqf expr value)
   (let (val value)
     (print-check-e expr eqf val)
     (test-check-e '(check eqf expr value) eqf (lambda () expr) val
                   (location expr)))))

(defrules check-eq? ()
  ((_ expr value)
   (checkf eq? expr value)))

(defrules check-not-eq? ()
  ((_ expr value)
   (checkf not-eq? expr value)))

(def (not-eq? x y)
  (not (eq? x y)))

(defrules check-eqv? ()
  ((_ expr value)
   (checkf eqv? expr value)))

(defrules check-not-eqv? ()
  ((_ expr value)
   (checkf not-eqv? expr value)))

(def (not-eqv? x y)
  (not (eqv? x y)))

(defrules check-equal? ()
  ((_ expr value)
   (let (val value)
     (print-check-e expr equal? val)
     (test-check-e '(check equal? expr value) equal-values? (lambda () expr) val
                   (location expr)))))

(defrules check-not-equal? ()
  ((_ expr value)
   (let (val value)
     (print-check-e expr equal? value)
     (test-check-e '(check not-equal? expr value) not-equal-values? (lambda () expr) val
                   (location expr)))))

(def (equal-values? obj-a obj-b)
  (if (##values? obj-a)
    (and (##values? obj-b)
         (equal? (##vector->list obj-a)
                 (##vector->list obj-b)))
    (equal? obj-a obj-b)))

(def (not-equal-values? x y)
  (not (equal-values? x y)))

(defrules check-output ()
  ((_ expr value)
   (let (val value)
     (verbose "... check ~a outputs ~s~n" 'expr val)
     (test-check-output '(check-output expr value) (lambda () expr) value
                        (location expr)))))

(defrules check-predicate ()
  ((_ expr pred)
   (begin
     (verbose "... check ~a is ~a~n" 'expr 'pred)
     (test-check-predicate '(check-predicate expr pred)  (lambda () expr) pred
                           (location expr)))))

(defrules check-exception ()
  ((_ expr exn-pred)
   (begin
     (verbose "... check ~a raises ~a~n" 'expr 'exn-pred)
     (test-check-exception '(check-exception expr exn-pred) (lambda () expr) exn-pred
                           (location expr)))))

(defsyntax (location stx)
  (syntax-case stx ()
    ((_ expr)
     (with-syntax ((loc
                    (cond
                     ((stx-source #'expr)
                      => (lambda (loc)
                           (call-with-output-string "" (cut ##display-locat loc #t <>))))
                     (else '?))))
       #'(quote loc)))))

(def (with-check-error thunk what loc)
  (try
   (thunk)
   (catch (e)
     (raise (make-!check-error e what loc)))))

(def current-test-case
  (make-parameter #f))
(def current-test-suite
  (make-parameter #f))
(def *tests* [])

(def (make-test-suite desc thunk)
  (make-!test-suite desc thunk []))

(def (run-tests! suite . more)
  (test-begin!)
  (run-test-suite! suite)
  (for-each run-test-suite! more))

(def (test-report-summary!)
  (let (tests (reverse *tests*))
    (unless (null? tests)
      (eprintf "--- Test Summary\n")
      (for-each test-suite-summary! tests)
      (eprintf "~a~n" (test-result)))))

(def (test-result)
  (let lp ((rest *tests*))
    (match rest
      ([suite . rest]
       (if (ormap (? (or !test-case-fail !test-case-error))
                  (!test-suite-tests suite))
         'FAILURE
         (lp rest)))
      (else 'OK))))

(def (test-suite-summary! suite)
  (def (print-failed tc)
    (cond
     ((!test-case-fail tc)
      => (lambda (fail)
           (eprintf "~a: Check FAILED ~a at ~a~n"
                    (!test-case-desc tc)
                    (!check-fail-e fail)
                    (!check-fail-loc fail))))
     ((!test-case-error tc)
      => (lambda (exn)
           (eprintf "~a: ERROR " (!test-case-desc tc))
           (display-exception exn (current-error-port))))))

  (let (tests (!test-suite-tests suite))
    (if (ormap (? (or !test-case-fail !test-case-error))
               tests)
      (begin
        (eprintf "~a: FAILED~n" (!test-suite-desc suite))
        (for-each print-failed tests))
    (eprintf "~a: OK~n" (!test-suite-desc suite)))))

(def (test-begin!)
  (set! *tests* []))

(def (test-add-test! suite)
  (push! suite *tests*))

(def (run-test-suite! suite)
  (test-suite-begin! suite)
   (parameterize ((current-test-suite suite))
     ((!test-suite-thunk suite)))
   (test-suite-end! suite))

(def (test-suite-begin! suite)
  (set! (!test-suite-tests suite) [])
  (test-add-test! suite)
  (eprintf "Test suite: ~a~n" (!test-suite-desc suite)))

(def (test-suite-end! suite)
  (if (find (? (or !test-case-fail !test-case-error))
            (!test-suite-tests suite))
    (eprintf "*** Test FAILED~n")
    (eprintf "... All tests OK~n")))

(def (test-suite-add-test! suite tc)
  (set! (!test-suite-tests suite)
    (cons tc (!test-suite-tests suite))))

(def (run-test-case! desc thunk)
  (let (tc (make-!test-case desc 0 #f #f))
    (test-case-begin! tc)
    (try
     (parameterize ((current-test-case tc))
       (thunk))
     (catch (!check-fail? e)
       (set! (!test-case-fail tc) e))
     (catch (e)
       (set! (!test-case-error tc) e)))
    (when *test-verbose*
      (force-output))
    (test-case-end! tc)))

(def (test-case-begin! tc)
  (eprintf "Test case: ~a~n" (!test-case-desc tc))
  (cond
   ((current-test-suite)
    => (cut test-suite-add-test! <> tc))))

(def (test-case-end! tc)
  (cond
   ((!test-case-fail tc)
    => (lambda (fail)
         (eprintf "*** FAILED: ~a at ~a; value: ~s~n"
                  (!check-fail-e fail)
                  (!check-fail-loc fail)
                  (!check-fail-value fail))))
   ((!test-case-error tc)
    => (lambda (e)
         (eprintf "*** ERROR: ")
         (display-exception e (current-error-port))))
   (else
    (eprintf "... ~a checks OK~n" (!test-case-checks tc)))))

(def (test-case-add-check! tc)
  (when tc
    (set! (!test-case-checks tc)
      (fx1+ (!test-case-checks tc)))))

(def (test-check-e what eqf thunk value loc)
  (test-case-add-check! (current-test-case))
  (let (val (with-check-error thunk what loc))
    (unless (eqf val value)
      (raise (make-!check-fail what val loc)))))

(def (test-check-output what thunk value loc)
  (test-case-add-check! (current-test-case))
  (let (val (with-output-to-string [] (cut with-check-error thunk what loc)))
    (unless (equal? val value)
      (raise (make-!check-fail what val loc)))))

(def (test-check-predicate what thunk pred loc)
  (test-case-add-check! (current-test-case))
  (let (val (with-check-error thunk what loc))
    (unless (pred val)
      (raise (make-!check-fail what val loc)))))

(def (test-check-exception what thunk pred loc)
  (test-case-add-check! (current-test-case))
  (let/cc success
    (let/cc fail-to-throw
      (let ((val (with-catch values (lambda () (thunk) (fail-to-throw)))))
        (if (pred val)
          (success)
          (raise (make-!check-fail what val loc)))))
    (raise (make-!check-fail what '(failed to throw an exception) loc))))
