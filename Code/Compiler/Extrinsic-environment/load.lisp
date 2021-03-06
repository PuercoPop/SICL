(cl:in-package #:sicl-extrinsic-environment)

(defun load (file environment)
  (with-open-file (stream file :direction :input)
    (let ((*package* (sicl-env:special-variable '*package* environment)))
      (loop with eof = (list nil)
	    for form = (sicl-reader:read stream nil eof)
	    until (eq form eof)
	    do (cleavir-env:eval form environment environment)
	       ;; The evaluation of the form might have change the
	       ;; value of the variable *PACKAGE* in the target
	       ;; environment.  But this function is executed as a
	       ;; host function, so the next time we call READ, we
	       ;; need to make sure the host variable *PACKAGE* also
	       ;; changes.
	       (setf *package*
		     (sicl-env:special-variable '*package* environment))))))

;;; This version of the function LOAD takes two environment objects.
;;; See section 3.2.1 in the HyperSpec for a description of the role
;;; of COMPILATION-ENVIRONMENT.  The LINKAGE-ENVIRONMENT is similar to
;;; what is called the RUN-TIME environment in section 3.2.1.  For
;;; SICL, it is more appropriate to call it the LINKAGE-ENVIRONMENT.
;;; It is the environment used to look up runtime definitions of
;;; functions and variables, whereas the code could very well be
;;; executed in a different environment.
(defun load-source-with-environments
    (file compilation-environment linkage-environment)
  (with-open-file (stream file :direction :input)
    (let ((*package* (sicl-env:special-variable '*package*
						compilation-environment)))
      (loop with eof = (list nil)
	    for form = (sicl-reader:read stream nil eof)
	    until (eq form eof)
	    do (cleavir-env:eval
		form compilation-environment linkage-environment)
	       ;; The evaluation of the form might have change the
	       ;; value of the variable *PACKAGE* in the target
	       ;; environment.  But this function is executed as a
	       ;; host function, so the next time we call READ, we
	       ;; need to make sure the host variable *PACKAGE* also
	       ;; changes.
	       (setf *package*
		     (sicl-env:special-variable '*package*
						linkage-environment))))))
