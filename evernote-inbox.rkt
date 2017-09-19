#lang racket

(require web-server/servlet-env)
(require
  (only-in "./evernote-ui.rkt"
           render-inbox-index))

(serve/servlet render-inbox-index
               #:port 8080
               #:launch-browser? #f)
