#lang racket

(define (remove-xexpr body xexpr-to-remove)
  (cond [(equal? body xexpr-to-remove) ""]
        [(list? body)
         (define body-parts (extract-xexpr body))
         `(,(first body-parts)
           ,(second body-parts)
           ,@(map (lambda (b) (remove-xexpr b xexpr-to-remove))
                  (third body-parts)))]
        [else body]))

(define (extract-xexpr xexpr)
  (match xexpr
    [(list (and (? symbol?) (var tag))
           (and (list (list (? symbol?)
                            (? string?)) ...)
                (var attrs))
           body ...)
     (list tag attrs body)]
    [(list (and (? symbol?) (var tag))
           body ...)
     (list tag null body)]
    [(var x)
     (list null null x)]))

(provide (all-defined-out))