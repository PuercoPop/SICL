(in-package #:sicl-compiler-phase-2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compilation context.
;;;
;;; Each AST is compiled in a particular COMPILATION CONTEXT or
;;; CONTEXT for short.  A context object has three components: 
;;;
;;; 1. RESULTS which indicates how many values are required from the
;;; compilation of this AST.  The results can be either a proper list
;;; or T.  If it is a proper list, then it contains a list of lexical
;;; locations into which the generated code must put the values of
;;; this AST.  If the list is empty, it means that no values are
;;; required.  If the list contains more elements than the number of
;;; values generated by this AST, then the remaining lexical locations
;;; in the list must be filled with NIL by the code generated from
;;; this AST.  If the RESULTS component is T, this means that all the
;;; values that this AST generates are required.
;;;
;;; 2. SUCCESSORS which is a proper list containing one or two
;;; elements.  These elements are instructions resulting from the
;;; generation of the code that should be executed AFTER the code
;;; generated from this AST.  If the list contains two elements, then
;;; this AST is compiled in a context where a Boolean result is
;;; required.  In this case, the first element of the list is the
;;; successor to use when the value generated by the AST is NIL, and
;;; the second element is the successor to use when the value
;;; generated by the AST is something other than NIL.
;;;
;;; 3. FALSE-REQUIRED-P, which is a Boolean value indicating whether a
;;; NIL Boolean value is required as explained below.
;;;
;;; The following combinations can occur:
;;;
;;;  * There is a single successor.  Then any RESULTS are possible.
;;;    FALSE-REQUIRED-P is ignored.
;;;
;;;  * There are two successors and the RESULTS is the empty list.
;;;    Then the generated code should determine whether the AST
;;;    generates a false or a true value and select the appropriate
;;;    successor.  FALSE-REQUIRED-P is ignored.  Such a context is
;;;    used to compile the test of an IF form.  The two successors
;;;    then correspond to the code for the ELSE branch and the code
;;;    for the THEN branch respectively. 
;;;
;;;  * There are two successors and the RESULTS is a list with more
;;;    than one element.  FALSE-REQUIRED-P is ignored.  The code
;;;    generated from the AST should do two things.  Code should be
;;;    generated to assign values to the results, and according to
;;;    whether the FIRST value is false or true, the appropriate
;;;    successor should be selected.  This kind of context could be
;;;    used to compile the FORM in (if (setf (values x y) FORM) ...).
;;;
;;;  * There are two successors and the RESULTS is a list with exactly
;;;    one element.  FALSE-REQUIRED-P is true.  The code generated
;;;    from the AST should do two things.  First, it should generate
;;;    code to compute the value from the AST and store it in the
;;;    result.  Next, it should determine whether that value is false
;;;    or true, and select the appropriate successor.  This kind of
;;;    context could be used to compile the FORM in code such as 
;;;    (if (setq x FORM) ...)
;;;
;;;  * There are two successors and the RESULTS is a list with exactly
;;;    one element.  FALSE-REQUIRED-P is false.  The code generated
;;;    should determine whether the result is false or true.  If it is
;;;    false, the first successor should be selected.  If it is true,
;;;    then that true value should be assigned to the lexical location
;;;    in RESULTS and the second successor should be selected.  This
;;;    kind of context could be used to compile FORM in code such as
;;;    (setq x (or FORM ...)). 

(defclass context ()
  ((%results :initarg :results :reader results)
   (%successors :initarg :successors :accessor successors)
   (%false-required-p :initarg :false-required-p :reader false-required-p)))

(defun context (results successors &optional (false-required-p t))
  (unless (or (eq results t)
	      (and (listp results)
		   (every (lambda (result)
			    (typep result 'sicl-env:lexical-location-info))
			  results)))
    (error "illegal results: ~s" results))
  (unless (and (listp successors)
	       (every (lambda (successor)
			(typep successor 'sicl-mir:instruction))
		      successors))
    (error "illegal successors: ~s" results))
  (if (and (= (length successors) 2)
	   (eq results t))
      (error "Illegal combination of results and successors")
      (make-instance 'context
		     :results results
		     :successors successors
		     :false-required-p false-required-p)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile an abstract syntax tree in a compilation context.
;;;
;;; The result of the compilation is a single value, namely the first
;;; instruction of the instruction graph resulting from the
;;; compilation of the entire AST.

(defun new-temporary ()
  (let ((name (gensym)))
    (make-instance 'sicl-env:lexical-location-info
      :location (sicl-env:make-lexical-location name)
      :type t
      :inline-info nil
      :ignore-info nil
      :dynamic-extent-p nil)))
  
;;; Given a list of results and a successor, generate a sequence of
;;; instructions preceding that successor, and that assign NIL to each
;;; result in the list.
(defun nil-fill (results successor)
  (let ((next successor))
    (loop for value in results
	  do (setf next
		   (sicl-mir:make-constant-assignment-instruction
		    value next nil))
	  finally (return next))))

(defgeneric compile-ast (ast context))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile ASTs that represent Common Lisp operations. 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile an IF-AST.  
;;;
;;; We compile the test of the IF-AST in a context where no value is
;;; required and with two successors, the else branch and the then
;;; branch.  The two branches are compiled in the same context as the
;;; IF-AST itself.

(defmethod compile-ast ((ast sicl-ast:if-ast) context)
  (let ((then-branch (compile-ast (sicl-ast:then-ast ast) context))
	(else-branch (compile-ast (sicl-ast:else-ast ast) context)))
    (compile-ast (sicl-ast:test-ast ast)
		 (context '() (list else-branch then-branch)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a PROGN-AST.
;;;
;;; The last sub-ast is compiled in the same context as the progn-ast
;;; itself.  All the others are copiled in a context where no value is
;;; required, and with the code for the following form as a single
;;; successor.

(defmethod compile-ast ((ast sicl-ast:progn-ast) context)
  (let ((next (compile-ast (car (last (sicl-ast:form-asts ast))) context)))
    (loop for sub-ast in (cdr (reverse (sicl-ast:form-asts ast)))
	  do (setf next (compile-ast sub-ast (context '() (list next)))))
    next))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a BLOCK-AST.
;;;
;;; A BLOCK-AST is compiled by compiling its body in the same context
;;; as the block-ast itself.  However, we store that context in the
;;; *BLOCK-INFO* hash table using the block-ast as a key, so that a
;;; RETURN-FROM-AST that refers to this block can be compiled in the
;;; same context.

(defparameter *block-info* nil)

(defmethod compile-ast ((ast sicl-ast:block-ast) context)
  (setf (gethash ast *block-info*) context)
  (compile-ast (sicl-ast:body-ast ast) context))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a RETURN-FROM-AST.
;;;
;;; A RETURN-FROM-AST is compiled as follows: The context is ignored,
;;; because the RETURN-FROM does not return a value in its own
;;; context.  Instead, the FORM-AST of the RETURN-FROM-AST is compiled
;;; in the same context as the corresponding BLOCK-AST was compiled
;;; in.

(defmethod compile-ast ((ast sicl-ast:return-from-ast) context)
  (declare (ignore context))
  (let ((block-context (gethash (sicl-ast:block-ast ast) *block-info*)))
    (compile-ast (sicl-ast:form-ast ast) block-context)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a TAGBODY-AST.
;;;
;;; A TAGBODY-AST is compiled as follows: A single successor is
;;; detemined.  If the RESULTS in the context is the empty list, i.e.,
;;; the value of this AST is not required at all, then the successor
;;; is the first of the list of successors received as an argument.
;;; It can never be the second one, because that one is taken only if
;;; the value of the AST is true, and the value of a TABODY-AST is
;;; always NIL.
;;;
;;; For each TAG-AST in the tagbody, a NOP instruction is created and
;;; that instruction is entered into the hash table *GO-INFO* using
;;; the TAG-AST as a key.  Then the items are compiled in the reverse
;;; order, stacking new instructions before the successor computed
;;; previously.  Compiling a TAG-AST results in the successor of the
;;; corresponding NOP instruction being modified to point to the
;;; remining instructions already computed.  Compiling something else
;;; is done in a context with an empty list of results, using the
;;; remaining instructions already computed as a single successor.

(defparameter *go-info* nil)

(defmethod compile-ast ((ast sicl-ast:tagbody-ast) context)
  (loop for item in (sicl-ast:items ast)
	do (when (typep item 'sicl-ast:tag-ast)
	     (setf (gethash item *go-info*)
		   (sicl-mir:make-nop-instruction nil))))
  (let ((next (if (null (results context))
		  (car (successors context))
		  (sicl-mir:make-variable-assignment-instruction
		   (sicl-mir:make-external-input 'nil)
		   (car (results context))
		   (car (successors context))))))
    (loop for item in (reverse (sicl-ast:items ast))
	  do (setf next
		   (if (typep item 'sicl-ast:tag-ast)
		       (let ((instruction (gethash item *go-info*)))
			 (setf (successors instruction) (list next))
			 instruction)
		       (compile-ast item (context '() (list next))))))
    next))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a GO-AST.
;;;
;;; The CONTEXT is ignored.  Instead, the successor becomes the NOP
;;; instruction that was entered into the hash table *GO-INFO* when
;;; the TAGBODY-AST was compiled.

(defmethod compile-ast ((ast sicl-ast:go-ast) context)
  (declare (ignore context))
  (gethash (sicl-ast:tag-ast ast) *go-info*))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a FUNCTION-CALL-AST.
;;;
;;; The first instruction generated is a PUT-ARGUMENTS-INSTRUCTION.
;;; This instruction supplies the arguments to the call.  Then the
;;; FUNCALL-INSTRUCTION is emitted.  Finally, if the FUNCTION-CALL-AST
;;; is compiled in a context where all the values are needed, i.e,
;;; with a RESULTS of T, then there is nothing more to do.
;;; Furthermore, in that case, there can only be a single successor.
;;;
;;; If the RESULTS is not T, then we must put the values generated by
;;; the call into the syntactic location indicated by the RESULTS.
;;; This is done by the GET-VALUES-INSTRUCTION.  That instruction may
;;; use one or two successors, in which case it tests the first value
;;; received and selects a successor based on whether that value is
;;; NIL or something else.

(defmethod compile-ast ((ast sicl-ast:call-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (let ((next (if (eq results t)
		    (car successors)
		    (sicl-mir:make-get-values-instruction
		     results (car successors)))))
      (let* ((all-args (cons (sicl-ast:callee-ast ast)
			     (sicl-ast:argument-asts ast)))
	     (temps (make-temps all-args)))
	(setf next
	      (sicl-mir:make-funcall-instruction
	       (car temps) next))
	(setf next
	      (sicl-mir:make-put-arguments-instruction (cdr temps) next))
	(setf next
	      (compile-arguments all-args temps next)))
      next)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a function consisting of an ordinary LAMBDA-LIST and a
;;; BODY-AST.  
;;;
;;; The result is a graph of instructions starting with a
;;; GET-ARGUMENTS-INSTRUCTION that uses the LAMBDA-LIST to supply
;;; values to the lexical locations that the body needs, and ending
;;; with a RETURN-INSTRUCTION which has no successors. 

(defun compile-function (lambda-list body-ast)
  (let ((next (sicl-mir:make-return-instruction)))
    (setf next (compile-ast body-ast (p2:context t (list next))))
    (sicl-mir:make-get-arguments-instruction next lambda-list)))
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a FUNCTION-AST.
;;;
;;; The FUNCTION-AST represents a closure, so we compile it by
;;; compiling its LAMBDA-LIST and BODY-AST into some code, represented
;;; by the first instruction in the body.  We then generate an
;;; ENCLOSE-INSTRUCTION that takes this code as input.
;;;
;;; The value computed by the FUNCTION-AST is always a function, so it
;;; is always a single non-NIL value.  If the value context is T,
;;; i.e., all the values are needed, we also generate a
;;; PUT-VALUES-INSTRUCTION with the single value as input.  If there
;;; is more than one successor, chose the second one for the true
;;; value. 

(defmethod compile-ast ((ast sicl-ast:function-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (let ((code (compile-function (sicl-ast:lambda-list ast)
				  (sicl-ast:body-ast ast)))
	  (next (if (= (length successors) 2)
		    (cadr successors)
		    (car successors))))
      (cond ((eq results t)
	     (let ((temp (new-temporary)))
	       (sicl-mir:make-enclose-instruction
		temp
		(sicl-mir:make-put-values-instruction (list temp) next)
		code)))
	    ((null results)
	     (warn "closure compiled in a context with no values"))
	    (t
	     (sicl-mir:make-enclose-instruction
	      (car results)
	      (nil-fill (cdr results) next)
	      code))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a SETQ-AST.

(defmethod compile-ast ((ast sicl-ast:setq-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    ;; FIXME: handle more situations here.
    (unless (and (null results)
		 (= (length successors) 1))
      (error "illegal context for setq"))
    (compile-ast (sicl-ast:value-ast ast)
		 (make-instance 'context
		   :successors successors
		   :results (list (sicl-ast:lhs-ast ast))
		   :false-required-p nil))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a LEXICAL-LOCATION-INFO object. 
;;;
;;; If the RESULTS is T, then we generate a PUT-VALUES-INSTRUCTION.
;;; In that case, we know that there is only one successor.  If there
;;; is a single successor and the RESULTS is the empty list, then a
;;; lexical variable occurs in a context where its value is not
;;; required, so we warn, and generate no additional code.  If there
;;; is a single successor and the RESULTS contains a single element,
;;; we generate a VARIABLE-ASSIGNMENT-INSTRUCTION.
;;;
;;; If there are two successors, we must generate a TEST-INSTRUCTION
;;; with those two successor.  If in addition the RESULTS is not
;;; the empty list, we must also generate a
;;; VARIABLE-ASSIGNMENT-INSTRUCTION.

(defmethod compile-ast ((ast sicl-env:lexical-location-info) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (ecase (length successors)
      (1 (cond ((eq results t)
		(sicl-mir:make-put-values-instruction
		 (list ast) (car successors)))
	       ((null results)
		(warn "variable compiled in a context with no values")
		(car successors))
	       ((eq ast (car results))
		(nil-fill (cdr results) (car successors)))
	       (t
		(sicl-mir:make-variable-assignment-instruction
		 ast
		 (car results) 
		 (nil-fill (cdr results) (car successors))))))
      (2 (if (or (null results) (eq ast (car results)))
	     (sicl-mir:make-test-instruction ast successors)
	     (sicl-mir:make-variable-assignment-instruction
	      ast
	      (car results)
	      (sicl-mir:make-test-instruction ast successors)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a GLOBAL-LOCATION-INFO object.
;;;
;;; We compile in the exact same way as the LEXICAL-LOCATION-INFO
;;; object.  

(defmethod compile-ast ((ast sicl-env:global-location-info) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (ecase (length successors)
      (1 (cond ((eq results t)
		(sicl-mir:make-put-values-instruction
		 (list ast) (car successors)))
	       ((null results)
		(warn "variable compiled in a context with no values")
		(car successors))
	       (t
		(sicl-mir:make-variable-assignment-instruction
		 ast
		 (car results)
		 (nil-fill (cdr results) (car successors))))))
      (2 (if (null results)
	     (sicl-mir:make-test-instruction ast successors)
	     (sicl-mir:make-variable-assignment-instruction
	      ast (car results) successors))))))

(defun compile-toplevel (ast)
  (let ((*block-info* (make-hash-table :test #'eq))
	(*go-info* (make-hash-table :test #'eq))
	(end (sicl-mir:make-end-instruction)))
    (compile-ast ast (context t (list end)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile ASTs that represent low-level operations.

(defun make-temp (argument)
  (cond ((typep argument 'sicl-env:lexical-location-info)
	 argument)
	((typep argument 'sicl-ast:immediate-ast)
	 (sicl-mir:make-immediate-input (sicl-ast:value argument)))
	((typep argument 'sicl-ast:load-time-value-ast)
	 (sicl-mir:make-external-input (sicl-ast:form-ast argument)))
	(t
	 (new-temporary))))

(defun make-temps (arguments)
  (loop for argument in arguments
	collect (make-temp argument)))

(defun compile-arguments (arguments temps successor)
  (loop with succ = successor
	for arg in (reverse arguments)
	for temp in (reverse temps)
	do (unless (or (typep temp 'sicl-mir:immediate-input)
		       (typep temp 'sicl-mir:external-input))
	     (setf succ (compile-ast arg (context (list temp) (list succ)))))
	finally (return succ)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a IMMEDATE-AST.
;;;

(defmethod compile-ast ((ast sicl-ast:immediate-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (unless (and (listp results)
		 (= (length results) 1)
		 (= (length successors) 1))
      (error "Invalid results for word."))
    (if (eq ast (car results))
	(car successors)
	(sicl-mir:make-constant-assignment-instruction
	 (car results)
	 (car successors)
	 (sicl-ast:value ast)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a MEMALLOC-AST.
;;;
;;; Allow only a context in which the RESULTS has exactly one
;;; element and in which there is a single successor.
;;;
;;; Allowing a results of T would mean that the result of this
;;; AST could be returned from a function, but since the result of
;;; this AST is not a tagged object, but a raw pointer, we cannot
;;; allow it to escape from the lexical locations of the function. 

(defmethod compile-ast ((ast sicl-ast:memalloc-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (unless (and (listp results)
		 (= (length results) 1)
		 (= (length successors) 1))
      (error "Invalid results for memalloc."))
    (let* ((temps (make-temps (sicl-ast:argument-asts ast)))
	   (instruction (sicl-mir:make-memalloc-instruction
			 (car temps) (car results) (car successors))))
      (compile-arguments (sicl-ast:argument-asts ast) temps instruction))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a MEMREF-AST.
;;;

(defmethod compile-ast ((ast sicl-ast:memref-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (let* ((temps (make-temps (sicl-ast:argument-asts ast)))
	   (instruction
	     (ecase (length successors)
	       (1 (let ((next (car successors)))
		    (cond ((null results)
			   (warn "MEMREF operation in a context of no results.")
			   next)
			  ((eq results t)
			   (let ((temp2 (new-temporary)))
			     (setf next 
				   (sicl-mir:make-put-values-instruction
				    (list temp2) next))
			     (sicl-mir:make-memref-instruction
			      (car temps) temp2 next)))
			  (t
			   (setf next (nil-fill (cdr results) next))
			   (sicl-mir:make-memref-instruction
			    (car temps) (car results) next)))))
	       (2 (if (eq results t)
		      (error "Illegal context for memref")
		      (let* ((location (if (null results)
					   (new-temporary)
					   (car results)))
			     (next (sicl-mir:make-test-instruction
				    location successors)))
			(setf next
			      (sicl-mir:make-memref-instruction
			       (car temps) location next))
			(nil-fill (cdr results) next)))))))
      (compile-arguments (sicl-ast:argument-asts ast) temps instruction))))

(defmethod compile-ast ((ast sicl-ast:memset-ast) context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (unless (and (= (length successors) 1)
		 (zerop (length results)))
      (error "Illegal context for memset."))
    (let* ((temps (make-temps (sicl-ast:argument-asts ast)))
	   (instruction
	     (sicl-mir:make-memset-instruction
	      temps (car successors))))
      (compile-arguments (sicl-ast:argument-asts ast) temps instruction))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compiling a simple arithmetic operation.

(defun compile-simple-arithmetic (argument-asts constructor context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (let* ((temps (make-temps argument-asts))
	   (instruction
	     (ecase (length successors)
	       (1 (let ((next (car successors)))
		    (cond ((null results)
			   (warn "Arithmetic operation in a context of no results.")
			   next)
			  ((eq results t)
			   (let ((temp (new-temporary)))
			     (setf next 
				   (sicl-mir:make-put-values-instruction
				    (list temp) next))
			     (funcall constructor temps temp (list next))))
			  (t
			   (setf next (nil-fill (cdr results) next))
			   (funcall constructor
				    temps (car results) (list next))))))
	       (2 (if (or (eq results t) (> (length results) 1))
		      (error "Illegal context for simple arithmetic.")
		      (funcall constructor temps successors))))))
      (compile-arguments argument-asts temps instruction))))

(defmethod compile-ast ((ast sicl-ast:u+-ast) context)
  (compile-simple-arithmetic (sicl-ast:argument-asts ast)
			     #'sicl-mir:make-u+-instruction
			     context))

(defmethod compile-ast ((ast sicl-ast:u--ast) context)
  (compile-simple-arithmetic (sicl-ast:argument-asts ast)
			     #'sicl-mir:make-u--instruction
			     context))

(defmethod compile-ast ((ast sicl-ast:s+-ast) context)
  (compile-simple-arithmetic (sicl-ast:argument-asts ast)
			     #'sicl-mir:make-u--instruction
			     context))

(defmethod compile-ast ((ast sicl-ast:s--ast) context)
  (compile-simple-arithmetic (sicl-ast:argument-asts ast)
			     #'sicl-mir:make-u--instruction
			     context))

(defmethod compile-ast ((ast sicl-ast:neg-ast) context)
  (compile-simple-arithmetic (sicl-ast:argument-asts ast)
			     #'sicl-mir:make-u--instruction
			     context))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a logic operation.
;;;
;;; Logic operations are characterized by the fact that they compute a
;;; single value and that this value can not generate an overflow or a
;;; carry.  Therefore, the corresponding instruction must have a
;;; single successor.
;;;
;;; We can not exclude that the result of a logic operation is a
;;; tagged Lisp object, so we must be prepared for all possible
;;; result contexts. 

(defun compile-logic (argument-asts constructor context)
  (with-accessors ((results results)
		   (successors successors))
      context
    (unless (= (length successors) 1)
      (error "Logic operation must have a single successor."))
    (let* ((next (car successors))
	   (temps (make-temps argument-asts))
	   (instruction
	     (cond ((null results)
		    (warn "Logic operation in a context of no results.")
		    next)
		   ((eq results t)
		    (let ((temp (new-temporary)))
		      (setf next 
			    (sicl-mir:make-put-values-instruction
			     (list temp) next))
		      (funcall constructor temps temp next)))
		   (t
		    (setf next (nil-fill (cdr results) next))
		    (funcall constructor temps (car results) next)))))
      (compile-arguments argument-asts temps instruction))))

      
(defmethod compile-ast ((ast sicl-ast:&-ast) context)
  (compile-logic (sicl-ast:argument-asts ast)
		 #'sicl-mir:make-&-instruction
		 context))

(defmethod compile-ast ((ast sicl-ast:ior-ast) context)
  (compile-logic (sicl-ast:argument-asts ast)
		 #'sicl-mir:make-ior-instruction
		 context))

(defmethod compile-ast ((ast sicl-ast:xor-ast) context)
  (compile-logic (sicl-ast:argument-asts ast)
		 #'sicl-mir:make-xor-instruction
		 context))

(defmethod compile-ast ((ast sicl-ast:~-ast) context)
  (compile-logic (sicl-ast:argument-asts ast)
		 #'sicl-mir:make-~-instruction
		 context))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Compile a test.

(defun make-boolean (boolean result successor)
  (sicl-mir:make-constant-assignment-instruction
   result successor boolean))

(defun compile-test (argument-asts constructor context)
  (with-accessors ((results results)
		   (successors successors)
		   (false-required-p false-required-p ))
      context
    (let* ((temps (make-temps argument-asts))
	   (instruction
	     (ecase (length successors)
	       (1 (let ((next (car successors)))
		    (cond ((null results)
			   (warn "Compilation of a test that is not used.")
			   next)
			  ((eq results t)
			   (let ((temp (new-temporary)))
			     (setf next 
				   (sicl-mir:make-put-values-instruction
				    (list temp) next))
			     (let ((false (make-boolean nil temp next))
				   (true (make-boolean t temp next)))
			       (funcall constructor temps (list false true)))))
			  (t
			   (setf next (nil-fill (cdr results) next))
			   (let ((false (make-boolean nil (car results) next))
				 (true (make-boolean t (car results) next)))
			     (funcall constructor temps (list false true)))))))
	       (2 (if (null results)
		      (funcall constructor temps successors)
		      (let ((next (funcall constructor temps successors)))
			(setf next (nil-fill (cdr results) next))
			(let ((false (if false-required-p
					 (make-boolean nil (car results) next)
					 next))
			      (true (make-boolean t (car results) next)))
			  (funcall constructor temps (list false true)))))))))
      (compile-arguments argument-asts temps instruction))))

(defmethod compile-ast ((ast sicl-ast:==-ast) context)
  (compile-test (sicl-ast:argument-asts ast)
		#'sicl-mir:make-==-instruction
		context))

(defmethod compile-ast ((ast sicl-ast:s<-ast) context)
  (compile-test (sicl-ast:argument-asts ast)
		#'sicl-mir:make-s<-instruction
		context))

(defmethod compile-ast ((ast sicl-ast:s<=-ast) context)
  (compile-test (sicl-ast:argument-asts ast)
		#'sicl-mir:make-s<=-instruction
		context))

(defmethod compile-ast ((ast sicl-ast:u<-ast) context)
  (compile-test (sicl-ast:argument-asts ast)
		#'sicl-mir:make-u<-instruction
		context))

(defmethod compile-ast ((ast sicl-ast:u<=-ast) context)
  (compile-test (sicl-ast:argument-asts ast)
		#'sicl-mir:make-u<=-instruction
		context))

