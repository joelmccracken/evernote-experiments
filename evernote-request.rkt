#lang racket

(require net/http-client
         json
         rackunit
         xml)

(define (request-inbox-items)
  (let-values ([(status resp-headers response)
                (http-sendrecv "localhost" "/inbox" #:port 4567)])
    (read-json response)))

(define (request-note-content guid)
  (let-values ([(status resp-headers response)
                (http-sendrecv "localhost"
                               (format "/notes/~a" guid)
                               #:port 4567)])
    (string->xexpr
     (hash-ref (read-json response)
               'content))))

(provide (all-defined-out))