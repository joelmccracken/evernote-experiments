#lang racket

(require
  xml
  web-server/http
  web-server/servlet
  (only-in "./evernote-request.rkt"
           request-inbox-items
           request-note-content)
  (only-in "./xexpr-utils.rkt"
           remove-xexpr
           extract-xexpr))

(require racket/pretty)

(define (debug-request message data request)
  (response/xexpr
   `(div ()
         (h1 () ,(format "Debug: ~s" message))
         (pre ()
              ,(pretty-format data)))))

(define (item-page item request embed/url)
  (define guid (hash-ref item 'guid))
  (define content (request-note-content guid))
  (render-item-page item content request embed/url))

(define (render-item-page item content request embed/url)
  (define guid (hash-ref item 'guid))
  (response/xexpr
   `(div (h1 ,(hash-ref item
                        'title))
         (h2 ,guid)
         (a ((href ,(embed/url (curry debug-request
                                      "Refile"
                                      (list item
                                            guid
                                            content)))))
            "Refile")
         (p ,(process-for-display item
                                  content
                                  embed/url)))))

(define (render-item-link embed/url item)
  (define (goto-item request)
    (item-page item request embed/url))
  `(li (a ((href ,(embed/url goto-item)))
          ,(hash-ref item 'title))))

(define (render-inbox-index request)
  (send/suspend/dispatch
   (lambda (embed/url)
     (response/xexpr
      `(ul
        ,@(map ((curry render-item-link) embed/url)
               (request-inbox-items)))))))

(define (remove-element-page item to-remove body request)
  (define content-without (remove-xexpr body to-remove))  
  (define (yes-really-remove request)
    (send/suspend/dispatch
     (lambda (embed/url)       
       (render-item-page item content-without request embed/url))))
  
  (send/suspend/dispatch
   (lambda (embed/url)
     (response/xexpr
      `(div (h1 () "Really rm link?")
            (div ()
                 (div ()
                      (a ((href ,(embed/url yes-really-remove)))
                         "Yes, really remove."))
                 ,(format "~a" to-remove)
                 ,content-without))))))

(define/contract (process-for-display item content embed/url)
  (hash? xexpr? any/c . -> . xexpr?)
  
  (define (removal-link attrs body)
    `(a ((href ,(embed/url (curry remove-element-page
                                  item
                                  `(a ,attrs
                                      ,@body)
                                  content))))
        "(REMOVE)"))
  
  (define/contract (process-tag tag attrs body)
    (symbol? any/c (listof xexpr?) . -> . xexpr?)
    
    (let ([processed-body
           (map process-for-display-
                body)])
      (if (equal? 'a tag)
          `(span ()
                 ,(append (list tag attrs) processed-body)
                 
                 ,(removal-link attrs body)
                 )
          (append (list tag attrs) processed-body))))
  
  (define (process-for-display- content)
    (match content
      [(list (? symbol?
                (var tag))
             (and (list x ...) (var attrs))
             body ...)
       (process-tag tag attrs body)]
      [else content]))
  
  (process-for-display- content))

(provide (all-defined-out))