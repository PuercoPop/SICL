(cl:in-package #:sicl-boot)

(defun customize-r2 (boot)
  (let ((c (c1 boot))
	(r (r2 boot)))
    (define-make-instance boot)
    (define-direct-slot-definition-class boot)
    (define-find-class boot)
    (ld "../CLOS/ensure-generic-function-using-class-support.lisp" c r)))