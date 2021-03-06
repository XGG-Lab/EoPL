(require eopl)

; BEGIN: Scanner
(define scanner-spec
  '((white-sp (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit))) symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)))

(define scan&parse
  (sllgen:make-string-parser scanner-spec grammar))

(define-datatype program program?
  (a-program (exp expression?)))

(define (type-of-program pgm)
  (cases program pgm
    (a-program (exp)
               (type-of exp (empty-tenv)))))

(define (run pgm)
  (type-of-program (scan&parse pgm)))

; BEGIN: Value type
(define (identifier? x)
  (symbol? x))

; BEGIN: Type
(define-datatype type type?
  (void-type)
  (int-type)
  (bool-type)
  (pair-type (ty1 type?)
             (ty2 type?))
  (listof (ty type?))
  (multi-type (types (list-of type?)))
  (refto (ty type?))
  (proc-type (arg-type type?)
             (result-type type?)))

(define (check-equal-type! ty1 ty2 exp)
  (if (equal? ty1 ty2)
      #t
      (report-unequal-types ty1 ty2 exp)))

(define (report-unequal-types ty1 ty2 exp)
  (eopl:error 'checck-equal-type!
              "Types didn't match: ~s != ~a in~%~a"
              (type-to-external-form ty1)
              (type-to-external-form ty2)
              exp))

(define (multi-type-rec types)
  (if (null? types)
      '()
      (cons '* (cons (type-to-external-form (car types))
                     (multi-type-rec (cdr types))))))

(define (type-to-external-form ty)
  (cases type ty
    (void-type () 'void)
    (int-type () 'int)
    (bool-type () 'bool)
    (pair-type (ty1 ty2)
               (list (type-to-external-form ty1)
                     '*
                     (type-to-external-form ty2)))
    (listof (ty)
            (list 'listof (type-to-external-form ty)))
    (multi-type (types)
                (if (equal? (length types) 1)
                    (type-to-external-form (car types))
                    (cdr (multi-type-rec types))))
    (refto (ty)
           (list 'refto (type-to-external-form ty)))
    (proc-type (args-type result-type)
               (list (type-to-external-form args-type)
                     '->
                     (type-to-external-form result-type)))))

; BEGIN: Environment
(define-datatype type-env type-env?
  (empty-tenv)
  (extend-tenv (var identifier?)
               (ty type?)
               (saved-tenv type-env?)))

(define (extend-tenv* vars types tenv)
  (if (null? vars)
      tenv
      (extend-tenv* (cdr vars) (cdr types)
                    (extend-tenv (car vars) (car types) tenv))))

(define (apply-tenv tenv search-var)
  (cases type-env tenv
    (empty-tenv ()
                (eopl:error 'apply-tenv "Unbound identifier: " search-var))
    (extend-tenv (var ty saved-tenv)
                 (if (equal? var search-var)
                     ty
                     (apply-tenv saved-tenv search-var)))))

; BEGIN: Grammar
(define grammar
  '((program (expression) a-program)
    (type ("int") int-type)
    (type ("bool") bool-type)
    (type ("(" type "->" type ")") proc-type)
    (expression (number) const-exp)
    (expression (identifier) var-exp)
    (expression ("newpair" "(" expression "," expression ")") pair-exp)
    (expression ("unpair" identifier identifier "=" expression "in" expression) unpair-exp)
    (expression ("list" "(" expression (arbno "," expression) ")") list-exp)
    (expression ("cons" "(" expression "," expression ")") cons-exp)
    (expression ("car" "(" expression ")") car-exp)
    (expression ("cdr" "(" expression ")") cdr-exp)
    (expression ("null?" "(" expression ")") null?-exp)
    (expression ("emptylist_" type) emptylist-exp)
    (expression ("newref" "(" expression ")") newref-exp)
    (expression ("deref" "(" expression ")") deref-exp)
    (expression ("setref" "(" expression "," expression ")") setref-exp)
    (expression ("set" identifier "=" expression) assign-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)
    (expression ("zero?" "(" expression ")") zero?-exp)
    (expression ("if" expression "then" expression "else" expression) if-exp)
    (expression ("let" (arbno identifier "=" expression) "in" expression) let-exp)
    (expression ("proc" "(" (arbno identifier ":" type) ")" expression) proc-exp)
    (expression ("letrec" (arbno type identifier "(" (arbno identifier ":" type ) ")" "=" expression)
                 "in" expression) letrec-exp)
    (expression ("(" expression (arbno expression) ")") call-exp)))

; BEGIN: Expression
(define-datatype expression expression?
  (const-exp (num number?))
  (var-exp (var identifier?))
  (pair-exp (exp1 expression?)
            (exp2 expression?))
  (unpair-exp (var1 identifier?)
              (var2 identifier?)
              (exp expression?)
              (body expression?))
  (list-exp (exp expression?)
            (exps (list-of expression?)))
  (cons-exp (exp1 expression?)
            (exp2 expression?))
  (car-exp (exp expression?))
  (cdr-exp (exp expression?))
  (null?-exp (exp expression?))
  (emptylist-exp (ty type?))
  (newref-exp (exp expression?))
  (deref-exp (var expression?))
  (setref-exp (var expression?)
              (exp expression?))
  (assign-exp (var identifier?)
              (exp expression?))
  (diff-exp (exp1 expression?)
            (exp2 expression?))
  (zero?-exp (exp1 expression?))
  (if-exp (cond expression?)
          (exp-t expression?)
          (exp-f expression?))
  (proc-exp (vars (list-of identifier?))
            (types (list-of type?))
            (body expression?))
  (let-exp (vars (list-of identifier?))
           (exps (list-of expression?))
           (body expression?))
  (letrec-exp (result-types (list-of type?))
              (names (list-of identifier?))
              (varss (list-of (list-of identifier?)))
              (var-types (list-of (list-of type?)))
              (exps (list-of expression?))
              (body expression?))
  (call-exp (rator expression?)
            (rands (list-of expression?))))

; BEGIN: Type-of
(define (map-of-two op a b)
  (if (null? a)
      '()
      (cons (op (car a) (car b))
            (map-of-two op (cdr a) (cdr b)))))

(define (type-of exp tenv)
  (cases expression exp
    (const-exp (num)
               (int-type))
    (var-exp (var)
             (apply-tenv tenv var))
    (pair-exp (exp1 exp2)
              (pair-type (type-of exp1 tenv)
                         (type-of exp2 tenv)))
    (unpair-exp (var1 var2 exp body)
                (let ((exp-type (type-of exp tenv)))
                  (cases type exp-type
                    (pair-type (ty1 ty2)
                               (type-of body (extend-tenv* (list var1 var2) (list ty1 ty2) tenv)))
                    (else (eopl:error 'type-of "Expression should be a pair: " exp)))))
    (list-exp (exp exps)
              (let ((ty (type-of exp tenv))
                    (types (map (lambda (exp) (type-of exp tenv)) exps)))
                (map (lambda (follow-type) (check-equal-type! ty follow-type exp)) types)
                (listof ty)))
    (cons-exp (exp1 exp2)
              (let ((ty1 (type-of exp1 tenv))
                    (ty2 (type-of exp2 tenv)))
                (cases type ty2
                  (listof (ty)
                          (check-equal-type! ty ty1 exp1)
                          ty2)
                  (else (eopl:error 'type-of "Expression should be a list: " exp2)))))
    (car-exp (exp)
             (let ((ty (type-of exp tenv)))
               (cases type ty
                 (listof (ty) ty)
                 (else (eopl:error 'type-of "Expression should be a list: " exp)))))
    (cdr-exp (exp)
             (let ((ty (type-of exp tenv)))
               (cases type ty
                 (listof (ty) (listof ty))
                 (else (eopl:error 'type-of "Expression should be a list: " exp)))))
    (null?-exp (exp)
               (let ((ty (type-of exp tenv)))
                 (cases type ty
                   (listof (ty)
                           (bool-type))
                   (else (eopl:error 'type-of "Expression should be a list: " exp)))))
    (emptylist-exp (ty)
                   (listof ty))
    (newref-exp (exp)
                (refto (type-of exp tenv)))
    (setref-exp (var exp)
                (void-type))
    (deref-exp (exp)
               (cases type (type-of exp tenv)
                 (refto (ty) ty)
                 (else (eopl:error 'type-of "Expression should be a reference: " exp))))
    (assign-exp (var exp)
                (type-of exp tenv))
    (diff-exp (exp1 exp2)
              (let ((ty1 (type-of exp1 tenv))
                    (ty2 (type-of exp2 tenv)))
                (check-equal-type! ty1 (int-type) exp1)
                (check-equal-type! ty2 (int-type) exp2)
                (int-type)))
    (zero?-exp (exp)
               (let ((ty (type-of exp tenv)))
                 (check-equal-type! ty (int-type) exp)
                 (bool-type)))
    (if-exp (exp1 exp2 exp3)
            (let ((ty1 (type-of exp1 tenv)))
              (check-equal-type! ty1 (bool-type) exp1)
              (let ((ty2 (type-of exp2 tenv))
                    (ty3 (type-of exp3 tenv)))
                (check-equal-type! ty2 ty3 exp)
                ty2)))
    (let-exp (vars exps body)
             (let ((types (map (lambda (exp) (type-of exp tenv)) exps)))
               (type-of body (extend-tenv* vars types tenv))))
    (letrec-exp (result-types names varss arg-typess exps body)
                (let* ((types (map-of-two (lambda (arg-types result-type)
                                            (proc-type (multi-type arg-types)
                                                       result-type))
                                          arg-typess
                                          result-types))
                       (body-tenv (extend-tenv* names types tenv)))
                  (define (check-rec varss arg-typess result-types exps)
                    (if (null? exps)
                        #t
                        (let ((exp-type (type-of (car exps) (extend-tenv* (car varss)
                                                                          (car arg-typess)
                                                                         body-tenv))))
                          (check-equal-type! (car result-types) exp-type (car exps))
                          (check-rec (cdr varss) (cdr arg-typess) (cdr result-types) (cdr exps)))))
                  (check-rec varss arg-typess result-types exps)
                  (type-of body body-tenv)))
    (proc-exp (vars types body)
              (let ((result-type (type-of body (extend-tenv* vars types tenv))))
                (proc-type (multi-type types) result-type)))
    (call-exp (rator rands)
              (let ((rator-type (type-of rator tenv))
                    (rands-type (multi-type (map (lambda (exp) (type-of exp tenv)) rands))))
                (cases type rator-type
                  (proc-type (args-type result-type)
                             (begin (check-equal-type! args-type rands-type rands)
                                    result-type))
                  (else (error 'type-of "Not a proc." exp)))))
    (else (eopl:error 'type-of exp))))

; BEGIN: Test
(define (equal?! prog expect)
  (let ((actual (type-to-external-form (run prog))))
    (display "Expect: ")
    (display expect)
    (display "\nActual: ")
    (display actual)
    (display "\n")
    (if (equal? actual expect)
        (display "\n")
        (display "Wrong Answer!!\n\n"))))

(define program-const "1")
(equal?! program-const 'int)

(define program-zero "zero?(0)")
(equal?! program-zero 'bool)

(define program-let "let x = 0 in x")
(equal?! program-let 'int)

(define program-diff "let x = 0 y = 1 in -(x, y)")
(equal?! program-diff 'int)

(define program-if "if zero?(0) then 1 else 2")
(equal?! program-if 'int)

(define program-proc "proc(a : int b : int) -(a, b)")
(equal?! program-proc '((int * int) -> int))

(define program-call "(proc(a : int b : int) -(a, b) 2 4)")
(equal?! program-call 'int)

(define program-letrec "letrec int f(n : int) = -(n, 1) bool g(n : int) = zero?(n) in newpair(f, g)")
(equal?! program-letrec '((int -> int) * (int -> bool)))

(define program-assign "let x = 1 in set x = zero?(0)")
(equal?! program-assign 'bool)

(define program-pair "unpair x y = newpair(1, zero?(0)) in newpair(x, y)")
(equal?! program-pair '(int * bool))

(define program-emptylist "emptylist_int")
(equal?! program-emptylist '(listof int))

(define program-list "list(1, 2, 3)")
(equal?! program-list '(listof int))

(define program-cons "cons(4, list(1, 2, 3))")
(equal?! program-cons '(listof int))

(define program-null "null?(cons(4, list(1, 2, 3)))")
(equal?! program-null 'bool)

(define program-car "car(list(1, 2, 3))")
(equal?! program-car 'int)

(define program-cdr "cdr(list(1, 2, 3))")
(equal?! program-cdr '(listof int))

(define program-newref "newref(5)")
(equal?! program-newref '(refto int))

(define program-deref "deref(newref(5))")
(equal?! program-deref 'int)

(define program-setref "setref(newref(5), 12)")
(equal?! program-setref 'void)
