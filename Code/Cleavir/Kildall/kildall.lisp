(in-package #:cleavir-kildall)

;;;; Iterative implementation of Kildall's algorithm.
;;;; TODO: This could probably be done in parallel.

;;; The work-list is Kildall's "L".
;;; It consists of pairs (instruction . pool) where pool is a
;;; transferred pool that may or may not represent new information.
(defvar *work-list*)
(defvar *dictionary*)

;;; The initial work-list instructions vary with the traversal, but
;;; the initial pools are more easily controlled with entry-pool.
(defgeneric compute-initial-work-list
    (specialization initial-instruction))

(defmethod compute-initial-work-list
    ((specialization reverse-traverse) initial)
  ;; because functions don't always reach a return instruction,
  ;; we actually start with all instructions as entries.
  (let (result)
    (cleavir-ir:map-instructions-arbitrary-order
     (lambda (instruction)
       (push (cons instruction
		   (entry-pool specialization instruction))
	     result))
     initial)
    result))

(defmethod compute-initial-work-list
    ((specialization forward-traverse) initial)
  ;; FIXME: are there no other ways to begin? UNWIND?
  (let (result)
    (cleavir-ir:map-instructions-arbitrary-order
     (lambda (instruction)
       (when (typep instruction 'cleavir-ir:enter-instruction)
	 (push (cons instruction
		     (entry-pool specialization instruction))
	       result)))
     initial)
    result))

(defun add-work (instruction pool)
  (push (cons instruction pool) *work-list*))

;;; This file is steps A4 and A5 of the algorithm.

;;; TRANSFER implements what Kildall calls "optimization functions"
;;; Methods receive an instruction and an input pool and return
;;; values for output pools, as described in specialization.lisp,
;;; depending on the traversal.
(defgeneric transfer (specialization instruction pool))

;;; Instruction-level part of the algorithm (A4, A5). Shouldn't
;;; usually need to be specialized. Could be a normal function?
;;; new-in is the pool from the worklist, and usually isn't passed
;;; directly to TRANSFER.
;;; Called for effect.
(defgeneric process-instruction
    (specialization instruction new-in))

;;; Step A5 of the algorithm: actually doing a transfer.
;;; Mostly specialized just for traversal differences.
;;; Called for effect.
(defgeneric process-transfer (specialization instruction pool))

;;; Default method just decides whether there's no info.
(defmethod process-instruction (s instruction new-in)
  (multiple-value-bind (dict-in present-p)
      (instruction-pool instruction *dictionary*)
    (cond ((not present-p)
	   ;; no entry is present, so we go ahead.
	   ;; "no entry" is used as kildall's distinguished _1_.
	   (process-transfer s instruction new-in))
	  ((pool<= s dict-in new-in)
	   ;; no new information, so do nothing.
	   nil)
	  (t ; new information, use it
	   (process-transfer s instruction
			     (pool-meet s new-in dict-in))))))

;;; Put the new information into the dictionary before proceeding.
(defmethod process-transfer :before (s instruction pool)
  (declare (ignore s))
  (setf (instruction-pool instruction *dictionary*) pool))

;;; in cases where we traverse WITH control, and each successor
;;; receives the same pool
(defmethod process-transfer
    ((specialization forward-spread-traverse) instruction pool)
  (let ((out (transfer specialization instruction pool)))
    (dolist (succ (cleavir-ir:successors instruction))
      (add-work succ out))))

;;; WITH control but with distinct pools for successors
(defmethod process-transfer
    ((specialization forward-single-traverse) instruction pool)
  ;; 3+ successors not supported yet (ever?)
  (ecase (length (cleavir-ir:successors instruction))
    (0 nil)
    (1 (add-work
	(first (cleavir-ir:successors instruction))
	(transfer specialization instruction pool)))
    (2 (multiple-value-bind (left right)
	   (transfer specialization instruction pool)
	 (add-work
	  (first (cleavir-ir:successors instruction))
	  left)
	 (add-work
	  (second (cleavir-ir:successors instruction))
	  right)))))

;;; in cases where we traverse AGAINST control, and each
;;; predecessor receives the same pool
(defmethod process-transfer
    ((specialization reverse-spread-traverse) instruction pool)
  (let ((out (transfer specialization instruction pool)))
    (dolist (pred (cleavir-ir:predecessors instruction))
      (add-work pred out))))

;;; Main entry point.
(defun kildall (specialization initial-instruction)
  (let ((*work-list* (compute-initial-work-list
		      specialization
		      initial-instruction))
	(*dictionary* (make-dictionary)))
    (loop until (null *work-list*)
	  do (let ((work (pop *work-list*)))
	       (process-instruction specialization
				    (car work) (cdr work))))
    *dictionary*))
