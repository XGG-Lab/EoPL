(require eopl)

; BEGIN: Scanner
(define scanner-spec
  '((white-sp (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit))) symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)))

(define scan&parse
  (sllgen:make-string-parser scanner-spec grammar-cps-in))

(define-datatype program program?
  (cps-in-program (exp expression?))
  (cps-out-program (exp tf-exp?)))

(define (cps-out-of-program pgm)
  (cps-out-program
   (cases program pgm
     (cps-in-program (exp)
                     (cps-of-exps (list exp) (lambda (simples)
                                               (simple-exp->exp (car simples)))))
     (else (error 'value-of-program)))))

(define (transform pgm)
  (cps-out-of-program (scan&parse pgm)))

(define (run pgm)
  (cases program pgm
    (cps-out-program (exp)
                     (initialize-store!)
                     (value-of/k exp (empty-env)))
    (else (error 'run))))

; BEGIN: Value type
(define (identifier? x)
  (symbol? x))

(define (reference? v)
  (integer? v))

(define-datatype expval expval?
  (num-val
   (num number?))
  (bool-val
   (bool boolean?))
  (list-val
   (lst list?))
  (proc-val
   (proc proc?))
  (ref-val
   (ref reference?)))

(define (expval->num val)
  (cases expval val
    (num-val (num) num)
    (else (error 'num val))))

(define (expval->bool val)
  (cases expval val
    (bool-val (bool) bool)
    (else (error 'bool val))))

(define expval->list
  (lambda (val)
    (cases expval val
      (list-val (lst) lst)
      (else (error 'list val)))))

(define (expval->proc val)
  (cases expval val
    (proc-val (proc) proc)
    (else (error 'proc val))))

(define (expval->ref val)
  (cases expval val
    (ref-val (ref) ref)
    (else (error 'ref val))))

(define (expval->val val)
  (cases expval val
    (num-val (num) num)
    (bool-val (bool) bool)
    (list-val (lst) (map expval->val lst))
    (proc-val (proc) proc)
    (ref-val (ref) (list 'ref ref))))

; BEGIN: Store
(define (store? x)
  (list-of x))

(define (empty-store)
  (make-vector 0))

(define the-store 'uninitialized)

(define (get-store) the-store)

(define (initialize-store!)
  (set! the-store (empty-store)))

(define (newref val)
  (let* ((next-ref (vector-length the-store))
         (next-store (make-vector (+ next-ref 1) val)))
    (define (newref-rec idx)
      (if (equal? idx next-ref)
          0
          (begin (vector-set! next-store idx (vector-ref the-store idx))
                 (newref-rec (+ idx 1)))))
    (newref-rec 0)
    (set! the-store next-store)
    next-ref))

(define (deref ref)
  (vector-ref the-store ref))

(define (setref! ref val)
  (vector-set! the-store ref val)
  ref)

; BEGIN: Environment
(define-datatype environment environment?
  (empty-env)
  (extend-env-ref
   (var identifier?)
   (ref reference?)
   (old-env environment?)))

(define (apply-env-ref env search-var)
  (cases environment env
    (empty-env ()
               (error 'apply-env-ref "Unbound variable." search-var))
    (extend-env-ref (var ref old-env)
                    (if (eqv? search-var var)
                        ref
                        (apply-env-ref old-env search-var)))))

(define (apply-env-val env var)
  (deref (apply-env-ref env var)))

(define (extend-env-val var val old-env)
  (extend-env-ref var (newref val) old-env))

(define (extend-env-vals vars vals env)
  (if (null? vars)
      env
      (extend-env-vals (cdr vars) (cdr vals) (extend-env-val (car vars) (car vals) env))))

(define (extend-env-rec names varss exps old-env)
  (let ((next-env (extend-env-vals names
                                   (build-list (length names) (lambda (x) 'undefined))
                                   old-env)))
    (define (extend-env-rec-sub names varss exps)
      (if (null? names)
          next-env
          (let* ((ref (apply-env-ref next-env (car names)))
                 (proc (procedure (car varss) (car exps) next-env)))
            (setref! ref (proc-val proc))
            (extend-env-rec-sub (cdr names) (cdr varss) (cdr exps)))))
    (extend-env-rec-sub names varss exps)))

; BEGIN: Grammar
(define grammar-cps-in
  '((program (expression) cps-in-program)
    (expression (number) const-exp)
    (expression (identifier) var-exp)
    (expression ("+" "(" (separated-list expression ",") ")") sum-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)
    (expression ("zero?" "(" expression ")") zero?-exp)
    (expression ("cons" "(" expression "," expression ")") cons-exp)
    (expression ("car" "(" expression ")") car-exp)
    (expression ("cdr" "(" expression ")") cdr-exp)
    (expression ("list" "(" (arbno expression) ")") list-exp)
    (expression ("reverse" "(" expression ")") reverse-exp)
    (expression ("null?" "(" expression ")") null?-exp)
    (expression ("emptylist") emptylist-exp)
    (expression ("if" expression "then" expression "else" expression) if-exp)
    (expression ("let" (arbno identifier "=" expression) "in" expression) let-exp)
    (expression ("proc" "(" (arbno identifier) ")" expression) proc-exp)
    (expression ("letrec" (arbno identifier "(" (arbno identifier) ")" "=" expression)
                 "in" expression) letrec-exp)
    (expression ("(" expression (arbno expression) ")") call-exp)))

; BEGIN: Expression
(define-datatype expression expression?
  (const-exp (num number?))
  (var-exp (var identifier?))
  (sum-exp (exps (list-of expression?)))
  (diff-exp (exp1 expression?)
            (exp2 expression?))
  (zero?-exp (exp1 expression?))
  (cons-exp (exp1 expression?)
            (exp2 expression?))
  (car-exp (exp expression?))
  (cdr-exp (exp expression?))
  (list-exp (exps (list-of expression?)))
  (reverse-exp (exp expression?))
  (null?-exp (exp expression?))
  (emptylist-exp)
  (if-exp (cond expression?)
          (exp-t expression?)
          (exp-f expression?))
  (proc-exp (vars (list-of identifier?))
            (body expression?))
  (let-exp (vars (list-of identifier?))
           (exps (list-of expression?))
           (body expression?))
  (letrec-exp (names (list-of identifier?))
              (varss (list-of (list-of identifier?)))
              (exps (list-of expression?))
              (body expression?))
  (call-exp (rator expression?)
            (rand (list-of expression?))))

(define-datatype simple-exp simple-exp?
  (cps-const-exp (num number?))
  (cps-var-exp (var identifier?))
  (cps-sum-exp (exps (list-of simple-exp?)))
  (cps-diff-exp (exp1 simple-exp?)
                (exp2 simple-exp?))
  (cps-zero?-exp (exp simple-exp?))
  (cps-cons-exp (exp1 simple-exp?)
                (exp2 simple-exp?))
  (cps-car-exp (exp simple-exp?))
  (cps-cdr-exp (exp simple-exp?))
  (cps-list-exp (exps (list-of simple-exp?)))
  (cps-reverse-exp (exp simple-exp?))
  (cps-null?-exp (exp simple-exp?))
  (cps-emptylist-exp)
  (cps-proc-exp (vars (list-of identifier?))
                (body tf-exp?)))

(define-datatype tf-exp tf-exp?
  (simple-exp->exp (exp simple-exp?))
  (cps-let-exp (vars (list-of identifier?))
               (exps (list-of simple-exp?))
               (body tf-exp?))
  (cps-letrec-exp (names (list-of identifier?))
                  (varss (list-of (list-of identifier?)))
                  (exps (list-of tf-exp?))
                  (body tf-exp?))
  (cps-if-exp (cond simple-exp?)
              (exp-t tf-exp?)
              (exp-f tf-exp?))
  (cps-call-exp (rator simple-exp?)
                (rands (list-of simple-exp?))))

; BEGIN: Translation
(define (every? pred lst)
  (if (null? lst)
      #t
      (if (pred (car lst))
          (every? pred (cdr lst))
          #f)))

(define fresh-identifier
  (let ((sn 0))
    (lambda (identifier)  
      (set! sn (+ sn 1))
      (string->symbol
       (string-append (symbol->string identifier) "%" (number->string sn))))))

(define (make-send-to-cont k-exp simple)
  (cases simple-exp k-exp
    (cps-proc-exp (vars body)
                  (cps-let-exp vars (list simple) body))
    (else (cps-call-exp k-exp (list simple)))))

(define cps-of-exps
  (lambda (exps builder)
    (let cps-of-rest ((exps exps) (acc '()))
      (cond
        ((null? exps) (builder (reverse acc)))
        ((exp-simple? (car exps))
         (cps-of-rest (cdr exps)
                      (cons
                       (cps-of-simple-exp (car exps))
                       acc)))
        (else (let ((var (fresh-identifier 'var)))
                (cps-of-exp (car exps)
                            (cps-proc-exp (list var)
                                          (cps-of-rest (cdr exps)
                                                       (cons
                                                        (cps-of-simple-exp (var-exp var))
                                                        acc))))))))))

(define (cps-of-exp/ctx exp context)
  (if (exp-simple? exp)
      (context (cps-of-simple-exp exp))
      (let ((var (fresh-identifier 'var)))
        (cps-of-exp exp
                    (cps-proc-exp (list var)
                                  (context (cps-var-exp var)))))))

(define (exp-simple? exp)
  (cases expression exp
    (const-exp (num) #t)
    (var-exp (var) #t)
    (diff-exp (exp1 exp2)
              (and (exp-simple? exp1)
                   (exp-simple? exp2)))
    (zero?-exp (exp) (exp-simple? exp))
    (cons-exp (exp1 exp2)
              (and (exp-simple? exp1)
                   (exp-simple? exp2)))
    (car-exp (exp)
             (exp-simple? exp))
    (cdr-exp (exp)
             (exp-simple? exp))
    (list-exp (exps)
              (every? exp-simple? exps))
    (reverse-exp (exp)
                 (exp-simple? exp))
    (null?-exp (exp)
               (exp-simple? exp))
    (emptylist-exp () #t)
    (proc-exp (vars body) #t)
    (sum-exp (exps)
             (every? exp-simple? exps))
    (else #f)))

(define (cps-of-simple-exp exp)
  (cases expression exp
    (const-exp (num)
               (cps-const-exp num))
    (var-exp (var)
             (cps-var-exp var))
    (diff-exp (exp1 exp2)
              (cps-diff-exp (cps-of-simple-exp exp1)
                            (cps-of-simple-exp exp2)))
    (zero?-exp (exp)
               (cps-zero?-exp (cps-of-simple-exp exp)))
    (cons-exp (exp1 exp2)
              (cps-cons-exp (cps-of-simple-exp exp1)
                            (cps-of-simple-exp exp2)))
    (car-exp (exp)
             (cps-car-exp (cps-of-simple-exp exp)))
    (cdr-exp (exp)
             (cps-cdr-exp (cps-of-simple-exp exp)))
    (list-exp (exps)
              (cps-list-exp (map cps-of-simple-exp exps)))
    (reverse-exp (exp)
                 (cps-reverse-exp (cps-of-simple-exp exp)))
    (null?-exp (exp)
               (cps-null?-exp (cps-of-simple-exp exp)))
    (emptylist-exp ()
                   (cps-emptylist-exp))
    (proc-exp (vars body)
              (cps-proc-exp (append vars (list '%k-exp-s))
                            (cps-of-exp body (cps-var-exp '%k-exp-s))))
    (sum-exp (exps)
             (cps-sum-exp (map cps-of-simple-exp exps)))
    (else (error 'cps-of-simple-exp exp))))

(define (cps-of-exp exp k-exp)
  (cases expression exp
    (const-exp (num)
               (make-send-to-cont k-exp (cps-const-exp num)))
    (var-exp (var)
             (make-send-to-cont k-exp (cps-var-exp var)))
    (sum-exp (exps)
             (cps-of-sum-exp exps k-exp))
    (diff-exp (exp1 exp2)
              (cps-of-diff-exp exp1 exp2 k-exp))
    (zero?-exp (exp)
               (cps-of-zero?-exp exp k-exp))
    (cons-exp (exp1 exp2)
              (cps-of-cons-exp exp1 exp2 k-exp))
    (car-exp (exp)
             (cps-of-car-exp exp k-exp))
    (cdr-exp (exp)
             (cps-of-cdr-exp exp k-exp))
    (list-exp (exps)
              (cps-of-list-exp exps k-exp))
    (reverse-exp (exp)
                 (cps-of-reverse-exp exp k-exp))
    (null?-exp (exp)
               (cps-of-null?-exp exp k-exp))
    (emptylist-exp ()
                   (make-send-to-cont k-exp (cps-emptylist-exp)))
    (if-exp (cond exp-t exp-f)
            (cps-of-if-exp cond exp-t exp-f k-exp))
    (proc-exp (vars body)
              (make-send-to-cont k-exp (cps-proc-exp (append vars (list '%k-exp))
                                                     (cps-of-exp body (cps-var-exp '%k-exp)))))
    (let-exp (vars exps body)
             (cps-of-let-exp vars exps body k-exp))
    (letrec-exp (names varss exps body)
                (cps-of-letrec-exp names varss exps body k-exp))
    (call-exp (rator rands)
              (cps-of-call-exp rator rands k-exp))))

(define (cps-of-diff-exp exp1 exp2 k-exp)
  (cps-of-exp/ctx exp1
                  (lambda (simp1)
                    (cps-of-exp/ctx exp2
                                    (lambda (simp2)
                                      (make-send-to-cont k-exp
                                                         (cps-diff-exp simp1 simp2)))))))

(define (cps-of-sum-exp exps k-exp)
  (cps-of-exps exps
               (lambda (simples)
                 (make-send-to-cont k-exp (cps-sum-exp simples)))))

(define (cps-of-zero?-exp exp k-exp)
  (cps-of-exp/ctx exp
                  (lambda (simp)
                    (make-send-to-cont k-exp
                                       (cps-zero?-exp simp)))))

(define (cps-of-cons-exp exp1 exp2 k-exp)
  (cps-of-exp/ctx exp1
                  (lambda (simp1)
                    (cps-of-exp/ctx exp2
                                    (lambda (simp2)
                                      (make-send-to-cont k-exp
                                                         (cps-cons-exp simp1 simp2)))))))

(define (cps-of-car-exp exp k-exp)
  (cps-of-exp/ctx exp
                  (lambda (simp)
                    (make-send-to-cont k-exp
                                       (cps-car-exp simp)))))

(define (cps-of-cdr-exp exp k-exp)
  (cps-of-exp/ctx exp
                  (lambda (simp)
                    (make-send-to-cont k-exp
                                       (cps-cdr-exp simp)))))

(define (cps-of-list-exp exps k-exp)
  (cps-of-exps exps
               (lambda (simples)
                 (make-send-to-cont k-exp (cps-list-exp simples)))))

(define (cps-of-reverse-exp exp k-exp)
  (cps-of-exp/ctx exp
                  (lambda (simp)
                    (make-send-to-cont k-exp
                                       (cps-reverse-exp simp)))))

(define (cps-of-null?-exp exp k-exp)
  (cps-of-exps (list exp)
               (lambda (simples)
                 (make-send-to-cont k-exp (cps-null?-exp (car simples))))))

(define (cps-of-if-exp cond exp-t exp-f k-exp)
  (cps-of-exps (list cond)
               (lambda (simples)
                 (let ((var (fresh-identifier 'var)))
                   (cps-call-exp (cps-proc-exp (list var)
                                               (cps-if-exp (car simples)
                                                           (cps-of-exp exp-t (cps-var-exp var))
                                                           (cps-of-exp exp-f (cps-var-exp var))))
                                 (list k-exp))))))

(define (cps-of-let-exp vars exps body k-exp)
  (cps-of-exps exps
               (lambda (simples)
                 (cps-let-exp vars simples (cps-of-exp body k-exp)))))

(define (cps-of-letrec-exp names varss exps body k-exp)
  (cps-letrec-exp names
                  (map (lambda (vars)
                         (append vars (list 'k%00))) varss)
                  (map (lambda (exp)
                         (cps-of-exp exp (cps-var-exp 'k%00))) exps)
                  (cps-of-exp body k-exp)))

(define (cps-of-call-exp rator rands k-exp)
  (cps-of-exps (cons rator rands)
               (lambda (simples)
                 (cps-call-exp (car simples)
                               (append (cdr simples) (list k-exp))))))

; BEGIN: Evaluation
(define (sum lst)
  (if (null? lst)
      0
      (+ (car lst) (sum (cdr lst)))))

(define (value-of/k exp env)
  (cases tf-exp exp
    (simple-exp->exp (simple)
                     (value-of-simple-exp simple env))
    (cps-let-exp (vars exps body)
                 (let ((vals (map (lambda (simple) (value-of-simple-exp simple env)) exps)))
                   (value-of/k body (extend-env-vals vars vals env))))
    (cps-letrec-exp (p-names b-varss p-bodies letrec-body)
                    (value-of/k letrec-body (extend-env-rec p-names b-varss p-bodies env)))
    (cps-if-exp (simple1 body1 body2)
                (if (expval->bool (value-of-simple-exp simple1 env))
                    (value-of/k body1 env)
                    (value-of/k body2 env)))
    (cps-call-exp (rator rands)
                  (let ((rator-proc (expval->proc (value-of-simple-exp rator env)))
                        (rand-vals (map (lambda (simple) (value-of-simple-exp simple env)) rands)))
                    (apply-procedure/k rator-proc rand-vals)))))

(define (value-of-simple-exp exp env)
  (cases simple-exp exp
    (cps-const-exp (num)
                   (num-val num))
    (cps-var-exp (var)
                 (apply-env-val env var))
    (cps-sum-exp (exps)
                 (let ((vals (map (lambda (exp) (expval->num (value-of-simple-exp exp env))) exps)))
                   (num-val (sum vals))))
    (cps-diff-exp (exp1 exp2)
                  (let ((val1 (expval->num (value-of-simple-exp exp1 env)))
                        (val2 (expval->num (value-of-simple-exp exp2 env))))
                    (num-val (- val1 val2))))
    (cps-zero?-exp (exp)
                   (bool-val (zero? (expval->num (value-of-simple-exp exp env)))))
    (cps-cons-exp (exp1 exp2)
                  (let ((val1 (value-of-simple-exp exp1 env))
                        (val2 (value-of-simple-exp exp2 env)))
                    (let ((lst2 (expval->list val2)))
                      (list-val (cons val1 lst2)))))
    (cps-car-exp (exp1)
                 (let ((val1 (value-of-simple-exp exp1 env)))
                   (let ((lst1 (expval->list val1)))
                     (car lst1))))
    (cps-cdr-exp (exp1)
                 (let ((val1 (value-of-simple-exp exp1 env)))
                   (let ((lst1 (expval->list val1)))
                     (list-val (cdr lst1)))))
    (cps-list-exp (exps)
                  (list-val (map (lambda (exp) (value-of-simple-exp exp env)) exps)))
    (cps-reverse-exp (exp)
                     (list-val (reverse (expval->list (value-of-simple-exp exp env)))))
    (cps-null?-exp (exp1)
                   (let ((val1 (value-of-simple-exp exp1 env)))
                     (let ((lst1 (expval->list val1)))
                       (bool-val (null? lst1)))))
    (cps-emptylist-exp () (list-val '()))
    (cps-proc-exp (vars body)
                  (proc-val (procedure vars body env)))))

; BEGIN: Procedure
(define-datatype proc proc?
  (procedure (vars (list-of identifier?))
             (body tf-exp?)
             (saved-env environment?)))

(define apply-procedure/k
  (lambda (proc1 args)
    (cases proc proc1
      (procedure (vars body saved-env)
                 (value-of/k body (extend-env-vals vars args saved-env))))))

; BEGIN: Test
(define (equal?! prog expect)
  (let* ((cps-out (transform prog))
         (actual (expval->val (run cps-out))))
    (display cps-out)
    (display "\n")
    (display "Expect: ")
    (display expect)
    (display "\nActual: ")
    (display actual)
    (display "\n")
    (if (equal? actual expect)
        (display "\n")
        (display "Wrong Answer!!\n\n"))))

(define program-const "1")
(equal?! program-const 1)

(define program-zero "zero?(0)")
(equal?! program-zero #t)

(define program-diff "-(5, 2)")
(equal?! program-diff 3)

(define program-sum "+(1, 2, 3)")
(equal?! program-sum 6)

(define program-let "let x = 1 y = 3 in +(x, y)")
(equal?! program-let 4)

(define program-if "if zero?(0) then 1 else 2")
(equal?! program-if 1)

(define program-proc "let f = proc(n) -(n, 1) in (f 45)")
(equal?! program-proc 44)

(define program-letrec "
letrec f(n) = if zero?(n)
              then 1
              else if zero?(-(n, 1))
                   then 1
                   else +((f -(n, 1)), (f -(n, 2)))
in (f 10)")
(equal?! program-letrec 89)

(define program-list-simple "list(1 2 3)")
(equal?! program-list-simple '(1 2 3))

(define program-list "
let f = proc(n) -(n, 1)
in list((f 1) (f 2) (f 3))")
(equal?! program-list '(0 1 2))

(define program-car-cdr "
let f = proc(n) -(n, 1)
in car(cdr(list((f 1) (f 2) (f 3))))")
(equal?! program-car-cdr 1)

(define program-cons "
let f = proc(n) -(n, 1)
in cons(3, list((f 1) (f 2) (f 3)))")
(equal?! program-cons '(3 0 1 2))

(define program-null? "null?(emptylist)")
(equal?! program-null? #t)
