(require eopl)

(define scanner-spec
  '((white-sp (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit))) symbol)
    (number (digit (arbno digit)) number)))

(define scan&parse
  (sllgen:make-string-parser scanner-spec grammar))

(define report-expval-extractor-error
  (lambda (type val)
    (error type "Extraction type error: " val)))

(define run
  (lambda (string)
    (value-of-program (a-program (scan&parse string)))))

(define (empty-env)
  '())

(define (extend-env var val old-env)
  (cons (list var val) old-env))

(define extend-env-rec
  (lambda (names varss exps saved-env)
    (let ((vec (make-vector (length names))))
      (let ((new-env (extend-env names vec saved-env)))
        (define (extend-rec varss exps idx)
          (if (null? exps)
              new-env
              (begin (vector-set! vec idx (proc-val (procedure (car varss) (car exps) new-env)))
                     (extend-rec (cdr varss) (cdr exps) (+ idx 1)))))
        (extend-rec varss exps 0)))))

(define (extend-env-list vars vals env)
  (if (null? vars)
      env
      (extend-env-list (cdr vars) (cdr vals) (extend-env (car vars) (car vals) env))))

(define (apply-env env var)
  (cond ((null? env) (report-no-binding-found var))
        ((list? (caar env)) (define (apply-rec names idx)
                              (if (null? names)
                                  (apply-env (cdr env) var)
                                  (if (eqv? (car names) var)
                                      (vector-ref (cadar env) idx)
                                      (apply-rec (cdr names) (+ idx 1)))))
                            (apply-rec (caar env) 0))
        ((eqv? (caar env) var) (cadar env))
        (else (apply-env (cdr env) var))))

(define (environment? x) (list? x))

(define report-no-binding-found
  (lambda (search-var)
    (error 'apply-env "No binding for ~s" search-var)))

(define value-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (exp1)
                 (value-of exp1 (empty-env))))))

(define-datatype program program?
  (a-program
   (exp1 expression?)))

(define (identifier? x)
  (and (symbol? x)
       (not (eqv? x 'lambda))))

(define-datatype expval expval?
  (num-val
   (num number?))
  (bool-val
   (bool boolean?))
  (list-val
   (lst list?))
  (proc-val
   (proc proc?)))

(define expval->num
  (lambda (val)
    (cases expval val
      (num-val (num) num)
      (else (report-expval-extractor-error 'num val)))))

(define expval->bool
  (lambda (val)
    (cases expval val
      (bool-val (bool) bool)
      (else (report-expval-extractor-error 'bool val)))))

(define expval->list
  (lambda (val)
    (cases expval val
      (list-val (lst) lst)
      (else (report-expval-extractor-error 'list val)))))

(define expval->proc
  (lambda (val)
    (cases expval val
      (proc-val (proc) proc)
      (else (report-expval-extractor-error 'proc val)))))

(define expval->val
  (lambda (val)
    (cases expval val
      (num-val (num) num)
      (bool-val (bool) bool)
      (list-val (lst) (map expval->val lst))
      (proc-val (proc) proc))))

(define-datatype proc proc?
  (procedure
   (vars (list-of identifier?))
   (body expression?)
   (saved-env environment?)))

(define apply-procedure
  (lambda (proc1 args)
    (cases proc proc1
      (procedure (vars body saved-env)
                 (define (apply-procedure-rec vars vals env)
                   (if (null? vars)
                       (if (null? vals)
                           (value-of body env)
                           (apply-procedure (expval->proc (value-of body env)) vals))
                       (if (null? vals)
                           (procedure vars body env)
                           (apply-procedure-rec (cdr vars) (cdr vals)
                                                (extend-env (car vars) (car vals) env)))))
                 (apply-procedure-rec vars args saved-env)))))

(define grammar
  '((expression (number) const-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)
    (expression ("+" "(" expression "," expression ")") add-exp)
    (expression ("*" "(" expression "," expression ")") mul-exp)
    (expression ("/" "(" expression "," expression ")") quotient-exp)
    (expression ("zero?" "(" expression ")") zero?-exp)
    (expression ("equal?" "(" expression "," expression ")") equal?-exp)
    (expression ("less?" "(" expression "," expression ")") less?-exp)
    (expression ("greater?" "(" expression "," expression ")") greater?-exp)
    (expression ("minus" "(" expression ")") minus-exp)
    (expression ("if" expression "then" expression "else" expression) if-exp)
    (expression ("cond" (arbno expression "==>" expression) "end") cond-exp)
    (expression (identifier) var-exp)
    (expression ("let" (arbno identifier "=" expression) "in" expression) let-exp)
    (expression ("let*" (arbno identifier "=" expression) "in" expression) let*-exp)
    (expression ("cons" "(" expression "," expression ")") cons-exp)
    (expression ("car" "(" expression ")") car-exp)
    (expression ("cdr" "(" expression ")") cdr-exp)
    (expression ("null?" "(" expression ")") null?-exp)
    (expression ("emptylist") emptylist-exp)
    (expression ("list" "(" (separated-list expression ",") ")") list-exp)
    (expression ("unpack" (arbno identifier) "=" expression "in" expression) unpack-exp)
    (expression ("proc" "(" (arbno identifier) ")" expression) proc-exp)
    (expression ("traceproc" "(" (arbno identifier) ")" expression) traceproc-exp)
    (expression ("letproc" identifier "(" (arbno identifier) ")" expression "in" expression)
                letproc-exp)
    (expression ("letrec" (arbno identifier "(" (arbno identifier) ")" "=" expression)
                          "in" expression)
                letrec-exp)
    (expression ("(" expression (arbno expression) ")") call-exp)
    (expression ("print" "(" expression ")") print-exp)))

(define-datatype expression expression?
  (const-exp
   (num number?))
  (diff-exp
   (exp1 expression?)
   (exp2 expression?))
  (add-exp
   (exp1 expression?)
   (exp2 expression?))
  (mul-exp
   (exp1 expression?)
   (exp2 expression?))
  (quotient-exp
   (exp1 expression?)
   (exp2 expression?))
  (zero?-exp
   (exp1 expression?))
  (equal?-exp
   (exp1 expression?)
   (exp2 expression?))
  (less?-exp
   (exp1 expression?)
   (exp2 expression?))
  (greater?-exp
   (exp1 expression?)
   (exp2 expression?))
  (if-exp
   (exp1 expression?)
   (exp2 expression?)
   (exp3 expression?))
  (cond-exp
   (conds (list-of expression?))
   (exps (list-of expression?)))
  (var-exp
   (var identifier?))
  (let-exp
   (vars (list-of identifier?))
   (exps (list-of expression?))
   (body expression?))
  (let*-exp
   (vars (list-of identifier?))
   (exps (list-of expression?))
   (body expression?))
  (minus-exp
   (exp1 expression?))
  (cons-exp
   (exp1 expression?)
   (exp2 expression?))
  (car-exp
   (exp1 expression?))
  (cdr-exp
   (exp1 expression?))
  (null?-exp
   (exp1 expression?))
  (emptylist-exp)
  (list-exp
   (exps (list-of expression?)))
  (unpack-exp
   (vars (list-of identifier?))
   (exp1 expression?)
   (exp2 expression?))
  (proc-exp
   (vars (list-of identifier?))
   (body expression?))
  (traceproc-exp
   (vars (list-of identifier?))
   (body expression?))
  (letproc-exp
   (name identifier?)
   (vars (list-of identifier?))
   (exp expression?)
   (body expression?))
  (letrec-exp
   (names (list-of identifier?))
   (varss (list-of (list-of identifier?)))
   (exps (list-of expression?))
   (body expression?))
  (call-exp
   (rator expression?)
   (rand (list-of expression?)))
  (print-exp
   (exp1 expression?)))

(define value-of
  (lambda (exp env)
    (cases expression exp
      (const-exp (num) (num-val num))
      (var-exp (var) (apply-env env var))
      (diff-exp (exp1 exp2)
                (let ((val1 (value-of exp1 env))
                      (val2 (value-of exp2 env)))
                  (let ((num1 (expval->num val1))
                        (num2 (expval->num val2)))
                    (num-val
                     (- num1 num2)))))
      (add-exp (exp1 exp2)
               (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (num-val
                    (+ num1 num2)))))
      (mul-exp (exp1 exp2)
               (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (num-val
                    (* num1 num2)))))
      (quotient-exp (exp1 exp2)
               (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (num-val
                    (quotient num1 num2)))))
      (zero?-exp (exp1)
                 (let ((val1 (value-of exp1 env)))
                   (let ((num1 (expval->num val1)))
                     (if (zero? num1)
                         (bool-val #t)
                         (bool-val #f)))))
      (equal?-exp (exp1 exp2)
                  (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (bool-val
                    (= num1 num2)))))
      (less?-exp (exp1 exp2)
                  (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (bool-val
                    (< num1 num2)))))
      (greater?-exp (exp1 exp2)
                  (let ((val1 (value-of exp1 env))
                     (val2 (value-of exp2 env)))
                 (let ((num1 (expval->num val1))
                       (num2 (expval->num val2)))
                   (bool-val
                    (> num1 num2)))))
      (if-exp (exp1 exp2 exp3)
              (let ((val1 (value-of exp1 env)))
                (if (expval->bool val1)
                    (value-of exp2 env)
                    (value-of exp3 env))))
      (cond-exp (conds exps)
                (cond ((null? conds) (error 'cond "No condition matched"))
                      ((expval->bool (value-of (car conds) env))
                       (value-of (car exps) env))
                      (else
                       (value-of (cond-exp (cdr conds) (cdr exps)) env))))
      (let-exp (vars exps body)
               (let ((vals (map (lambda (exp) (value-of exp env)) exps)))
                 (value-of body (extend-env-list vars vals env))))
      (let*-exp (vars exps body)
                (if (null? vars)
                    (value-of body env)
                    (value-of (let*-exp (cdr vars) (cdr exps) body)
                              (extend-env (car vars) (value-of (car exps) env) env))))
      (minus-exp (exp1)
                 (num-val (- (expval->num (value-of exp1 env)))))
      (cons-exp (exp1 exp2)
                (let ((val1 (value-of exp1 env))
                      (val2 (value-of exp2 env)))
                  (let ((lst2 (expval->list val2)))
                    (list-val (cons val1 lst2)))))
      (car-exp (exp1)
               (let ((val1 (value-of exp1 env)))
                 (let ((lst1 (expval->list val1)))
                   (car lst1))))
      (cdr-exp (exp1)
               (let ((val1 (value-of exp1 env)))
                 (let ((lst1 (expval->list val1)))
                   (list-val (cdr lst1)))))
      (null?-exp (exp1)
                 (let ((val1 (value-of exp1 env)))
                   (let ((lst1 (expval->list val1)))
                     (bool-val (null? lst1)))))
      (emptylist-exp () (list-val '()))
      (list-exp (exps)
                (list-val (map (lambda (exp) (value-of exp env)) exps)))
      (unpack-exp (vars exp1 exp2)
              (let ((val1 (value-of exp1 env)))
                (let ((lst1 (expval->list val1)))
                  (define (unpack-rec vars lst env)
                    (if (null? vars)
                        env
                        (unpack-rec (cdr vars) (cdr lst) (extend-env (car vars) (car lst) env))))
                  (value-of exp2 (unpack-rec vars lst1 env)))))
      (proc-exp (vars body)
                (proc-val (procedure vars body env)))
      (traceproc-exp (vars body)
                     (print "Enter: ")
                     (print vars)
                     (print body)
                     (display "\n")
                     (let ((result (proc-val (procedure vars body env))))
                       (print "Leave: ")
                       (print vars)
                       (print body)
                       (display "\n")
                       result))
      (letproc-exp (name vars exp body)
                   (value-of body
                             (extend-env name
                                           (proc-val (procedure vars exp env))
                                           env)))
      (letrec-exp (names varss exps body)
                  (value-of body (extend-env-rec names varss exps env)))
      (call-exp (rator rand)
                (let ((proc (expval->proc (value-of rator env)))
                      (args (map (lambda (exp) (value-of exp env)) rand)))
                  (apply-procedure proc args)))
      (print-exp (exp1)
                 (print (expval->val (value-of exp1 env)))
                 (num-val 1)))))

(equal? (expval->val (run "letrec
                             even(x) = if zero?(x) then 1 else (odd -(x,1))
                             odd(x) = if zero?(x) then 0 else (even -(x,1))
                             gcd(x y) = if equal?(x, y)
                                        then x
                                        else if greater?(x, y)
                                             then (gcd -(x, y) y)
                                             else (gcd x -(y, x))
                           in -((odd 13), (gcd 14 100))")) -1)
