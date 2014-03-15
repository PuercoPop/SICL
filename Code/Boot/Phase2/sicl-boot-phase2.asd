(cl:in-package #:common-lisp-user)

(asdf:defsystem :sicl-boot-phase2
  :depends-on (:sicl-code-utilities
	       :sicl-additional-conditions
	       :sicl-boot-phase1)
  :serial t
  :components
  (;; Define package SICL-BOOT-PHASE2 which uses the COMMON-LISP
   ;; package and the ASPIRING-SICL-CLOS package.
   (:file "packages")
   ;; Define the package SICL-GLOBAL-ENVIRONMENT.  This package uses
   ;; the COMMON-LISP package, does not shadow any symbols, and
   ;; exports the names of all the classes and functions required to
   ;; manipulate a global environment.
   (:file "environment-packages")
   ;; Import and shadow symbols DEFCLASS, DEFGENERIC, and DEFMACRO
   ;; from the SICL-BOOT-PHASE2 package to the
   ;; SICL-GLOBAL-ENVIRONMENT, so that code that is loaded in the
   ;; package SICL-GLOBAL-ENVIRONMENT will use the definition of those
   ;; symbols in the SICL-BOOT-PHASE2 package.
   (:file "import-to-environment")
   ;; Add nickname SICL-CLOS to the SICL-BOOT-PHASE2 package so that
   ;; code that gets loaded in the SICL-CLOS package in reality gets
   ;; loaded into the SICL-BOOT-PHASE2 package. 
   (:file "rename-package-1")
   ;; Define an ordinary function named
   ;; SICL-BOOT-PHASE2:SHARED-INITIALIZE-DEFAULT and that calls the
   ;; function which is the value of the variable
   ;; *SHARED-INITIALIZE-DEFAULT*.  The initial value of this variable
   ;; is the function SICL-BOOT-PHASE1:SHARED-INITIALIZE-DEFAULT, so
   ;; that SHARED-INITIALIZE initializes an ersatz instance by
   ;; accessing the bridge class of that instance.  Later, when the
   ;; class of an ersatz instance is another ersatz instance, we
   ;; change the value of the variable to be a function that
   ;; initializes ersatz instances by accessing the ersatz class of
   ;; the ersatz instance.
   (:file "shared-initialize-default")
   ;; Up until now, the package named ASPIRING-SICL-CLOS contained
   ;; only the names of the specified classes whose names were not
   ;; exported from the package COMMON-LISP.  Now, we add names of
   ;; specified accessors to the package ASPIRING-SICL-CLOS so that
   ;; when we define bridge generic functions, their names will be
   ;; symbols in the package ASPIRING-SICL-CLOS. 
   (:file "import")
   ;; Define ordinary functions that do some of what the CL sequence
   ;; functions do, but that work only on lists.  We use these
   ;; functions to avoid using the sequence functions because we might
   ;; want to make the sequence functions generic, and we do not want
   ;; to invoke generic functions in order to compute the
   ;; discriminating function of generic functions.
   (:file "list-utilities")
   ;; Declare an ordinary function called FUNCTIONP and that always
   ;; returns true.  This function is used for error checking, and we
   ;; do not expect any errors during bootstrapping, so we can wing
   ;; it.
   (:file "functionp")
   ;; Define ordinary functions to be used by the expansion code for
   ;; DEFCLASS.  These functions are responsible for checking the
   ;; syntax of the DEFCLASS forms, and for canonicalizing superclass
   ;; specifications, slot specifications, and class options.
   (:file "defclass-support")
   ;; Define the macro SICL-BOOT-PHASE2:DEFCLASS.  It expands to a
   ;; call to ENSURE-CLASS.  The symbol SICL-BOOT-PHASE1:ENSURE-CLASS
   ;; is imported from phase 1, which means that this DEFCLASS will
   ;; create a bridge class.
   (:file "defclass-defmacro")
   ;; Define the macro SICL-BOOT-PHASE2:DEFINE-BUILT-IN-CLASS.  It
   ;; expands to a call to ENSURE-BUILT-IN-CLASS.  The symbol
   ;; SICL-BOOT-PHASE1:ENSURE-BUILT-IN-CLASS is imported from phase 1,
   ;; which means that this macro will create a built-in bridge class.
   (:file "define-built-in-class-defmacro")
   ;; Define the macro SICL-BOOT-PHASE2:DEFGENERIC.  It expands to a
   ;; call to ENSURE-GENERIC-FUNCTION.  The symbol
   ;; SICL-BOOT-PHASE1:ENSURE-GENERIC-FUNCTION is imported from phase
   ;; 1, which means that this DEFGENERIC will create a bridge generic
   ;; function.
   (:file "defgeneric-defmacro")
   ;; Define ordinary functions to be used by the expansion code for
   ;; DEFMETHOD.  These functions are responsible for checking the
   ;; syntax of the DEFMETHOD forms, and for canonicalizing the list
   ;; of specializers.
   (:file "defmethod-support")
   ;; Define the macro SICL-BOOT-PHASE2:DEFMETHOD.  It expands to a
   ;; call to ENSURE-METHOD.  The symbol
   ;; SICL-BOOT-PHASE1:ENSURE-METHOD is imported from phase 1, which
   ;; means that this DEFMETHOD will create a bridge method.
   (:file "defmethod-defmacro")
   ;; Define MAKE-METHOD-LAMBDA as an ordinary function.
   ;; MAKE-METHOD-LAMBDA is called by the expansion code of DEFMETHOD
   ;; in order to turn the method body into a lambda expression
   ;; suitable for method invocation. 
   (:file "make-method-lambda-support")
   (:file "make-method-lambda-defuns")
   ;; Load the hierarchy of MOP classes, which will create bridge
   ;; classes, bridge generic functions, bridge methods, and bridge
   ;; slot definitions.  All of these are instances of host classes. 
   (:file "mop-class-hierarchy")
   ;; Here in phase 2 is the right place to define bridge classes for
   ;; which the accessors are going to be used later during the
   ;; bootstrapping process, because those accessors will be the
   ;; FDEFINITION of the corresponding symbols, so they will be usable
   ;; as ordinary functions in the host bootstrapping environment.  In
   ;; later phases, defining classes and generic functions will define
   ;; ersatz generic functions which are not executable in the host
   ;; environment.  Since we are going to want to load up a global
   ;; ersatz environment with ersatz classes and ersatz functions, it
   ;; is handy (though not totally necessary, because we could use
   ;; reinitialize-instance) to have executable accessors for that
   ;; global ersatz environment.  This is why we include the
   ;; definition of environment classes here.
   (:file "environment-classes")
   (:file "environment-constructors")
   (:file "environment-query")
   ;; Now that we have all the bridge classes (but not all the bridge
   ;; generic functions) that we are ever going to define, it is time
   ;; to think about how to use those bridge classes and those bridge
   ;; generic functions in order to create ersatz instances.  As in
   ;; phase 1, there are a number of default values that are needed
   ;; during this process, such as the class named STANDARD-OBJECT,
   ;; the class named STANDARD-READER-METHOD.  These default values
   ;; are accessed as values of special variables.  This component
   ;; assigns meaning to those variables.
   (:file "define-variables")
   ;; Since we have all the bridge classes that we are ever going to
   ;; define, we finalize them all now.  FIXME: This step may actually
   ;; not be necessary.
   (:file "finalize-all-bridge-classes")
   ;; While we already have all the bridge classes we need, we need
   ;; more bridge generic functions.  The additional ones we need are
   ;; not accessors, but instead the entire remaining MOP machinery.
   ;; We can not define that machinery in the form of generic
   ;; functions here, because part of the purpose of the machinery is
   ;; to make generic functions work.  For that reason, we define the
   ;; machinery in the form of ordinary functions.  To begin with, we
   ;; define ordinary functions SICL-BOOT-PHASE1:ADD-DIRECT-METHOD and
   ;; SICL-BOOT-PHASE1:REMOVE-DIRECT-METHOD.  Recall that
   ;; ADD-DIRECT-METHOD is called to add a reference to a method from
   ;; a specializer (typically a class) used in that method.  It will
   ;; be called from ADD-METHOD when the MOP class hierarchy is used
   ;; in phase 3 to create ersatz classes, in order to add a reference
   ;; to an ersatz method from an ersatz class.
   (:file "add-remove-direct-method-support")
   (:file "add-remove-direct-method-defuns")
   ;; Define an ordinary function CLASSP that always returns true.
   ;; The function CLASSP is used for the purpose of error checking,
   ;; and during bootstrapping, we do not expect any errors, so we can
   ;; wing it.
   (:file "classp")
   ;; Define ordinary functions COMPUTE-APPLICABLE-METHODS and
   ;; COMPUTE-APPLICABLE-METHODS-USING-CLASSES.  Here they will be
   ;; ordinary functions that take ersatz generic functions as
   ;; arguments, and they will return lists of ersatz methods.  These
   ;; functions are called by COMPUTE-DISCRIMINATING-FUNCTION.
   (:file "compute-applicable-methods-support")
   (:file "compute-applicable-methods-defuns")
   ;; Define ordinary function COMPUTE-EFFECTIVE-METHOD.  The
   ;; effective method is computed from a sorted list of applicable
   ;; ersatz methods by first computing a form containing the
   ;; applicable methods as literals, and then calling the cross
   ;; compiler to turn all that into an ersatz function.  This
   ;; function is called by COMPUTE-DISCRIMINATING-FUNCTION.
   (:file "compute-effective-method-support")
   (:file "compute-effective-method-support-a")
   (:file "method-combination-compute-effective-method-support")
   (:file "method-combination-compute-effective-method-defuns")
   (:file "compute-effective-method-defuns")
   ;; Define ordinary functions for computing and minimizing the
   ;; discriminating automaton from the call history of a generic
   ;; function.  These functions are called by
   ;; COMPUTE-DISCRIMINATING-FUNCTION.
   (:file "discriminating-automaton")
   ;; Define ordinary functions for turning a discriminating automaton
   ;; into a discriminating tagbody form.  The tagbody form contains
   ;; effective methods as literals and is later compiled (using
   ;; the cross compiler) into an ersatz function.
   (:file "discriminating-tagbody")
   ;; Define function COMPILE to mean the cross compiler which creates
   ;; an ersatz function from a lambda expression.
   (:file "compile")
   ;; Define ordinary function COMPUTE-DISCRIMINATING-FUNCTION.  Here,
   ;; it will be used to compute the discriminating function of an
   ;; ersatz generic function.  The discriminating function will be
   ;; computed by calling the cross compiler on a lambda expression
   ;; consisting mainly of the TAGBODY form returned by the function
   ;; COMPUTE-DISCRIMINATING-TAGBODY defined above.
   (:file "compute-discriminating-function-support")
   (:file "compute-discriminating-function-support-a")
   (:file "compute-discriminating-function-defuns")
   ;; Although we do not use the dependent maintenance facility, we
   ;; define the specified functions as ordinary functions that do
   ;; nothing, so that we can safely call them from other code.
   (:file "dependent-maintenance-support")
   (:file "dependent-maintenance-defuns")
   ;; Define ordinary function SET-FUNCALLABLE-INSTANCE-FUNCTION to
   ;; set the funcallable instance function of an ersatz generic
   ;; function.  FIXME: right now, this function does nothing.  What
   ;; it should do is to copy the slots of the discriminating function
   ;; (which is an ordinary ersatz function) to the generic function
   ;; (which is an ersatz generic function). 
   (:file "set-funcallable-instance-function")
   ;; Define bridge generic functions SICL-BOOT-PHASE2:ADD-METHOD and
   ;; SICL-BOOT-PHASE2:REMOVE-METHOD.  The function ADD-METHOD will be
   ;; called from ADD-READER/WRITER-METHOD when the MOP class
   ;; hierarchy is used in phase 3 to generate ersatz classes.
   (:file "add-remove-method-support")
   (:file "add-remove-method-defgenerics")
   (:file "add-remove-method-defmethods")
   ;; When the support code for SHARED-INITIALIZE is used to
   ;; initialize an ersatz instance, it uses SLOT-BOUNDP-USING-CLASS
   ;; and (SETF SLOT-VALUE-USING-CLASS) to accomplish its task.  Here,
   ;; these two functions are passed an ersatz class (which is a host
   ;; instance) and an ersatz instance representing an effective slot
   ;; definition metaobject.  This is why these two functions are
   ;; defined here as bridge generic functions.
   (:file "slot-value-etc-defgenerics")
   (:file "slot-value-etc-support")
   (:file "slot-value-etc-defmethods")
   (:file "slot-value-etc-specified-defuns")
   ;; Define bridge generic functions INITIALIZE-INSTANCE,
   ;; REINITIALIZE-INSTANCE, and shared-initialize.
   (:file "initialize-instance-defgenerics")
   (:file "reinitialize-instance-defgenerics")
   (:file "shared-initialize-defgenerics")
   ;; Define ordinary functions constituting support code for
   ;; INITIALIZE-INSTANCE and REINITIALIZE-INSTANCE.  The function
   ;; SHARED-INITIALIZE-DEFAULT has already been defined before in
   ;; phase 2 to make an indirect call to the version of
   ;; SHARED-INITIALIZE-DEFAULT that we defined in phase 1, so we do
   ;; not include it here.
   (:file "initialize-instance-support")
   (:file "reinitialize-instance-support")
   ;; Define bridge methods on INITIALIZE-INSTANCE,
   ;; REINITIALIZE-INSTANCE, and shared-initialize.
   (:file "initialize-instance-defmethods")
   (:file "reinitialize-instance-defmethods")   
   (:file "shared-initialize-defmethods")
   ;; Define INITIALIZE-BUILT-IN-INSTANCE as a bridge generic
   ;; function, and default method.
   (:file "initialize-built-in-instance-defgenerics")
   (:file "initialize-built-in-instance-defmethods")
   ;; Define an ordinary function SPECIALIZERP that always returns
   ;; true.  This function is used only for error checking, and during
   ;; bootstrapping, we do not expect this kind of error.
   (:file "specializerp")
   ;; Define bridge generic functions
   ;; SICL-BOOT-PHASE2:READER-METHOD-CLASS and
   ;; SICL-BOOT-PHASE2:WRITER-METHOD-CLASS and methods on these
   ;; functions that return whatever *STANDARD-READER-METHOD* and
   ;; *STANDARD-WRITER-METHOD* stand for.  These functions will be
   ;; called from ADD-READER/WRITER-METHOD when the MOP class
   ;; hierarchy is used in phase 3 to generate ersatz classes by
   ;; instantiating bridge classes.  Therefore, the classes that they
   ;; should return are bridge classes, so that when ersatz classes
   ;; and ersatz generic functions are created by instantiating bridge
   ;; classes, the methods that are created are ersatz methods.  This
   ;; is why the variables *STANDARD-READER-METHOD* and
   ;; *STANDARD-WRITER-METHOD* contain bridge classes, as can be seen
   ;; in the component define-variables.lisp
   (:file "reader-writer-method-class-support")
   (:file "reader-writer-method-class-defgenerics")
   (:file "reader-writer-method-class-defmethods")
   ;; Define an ordinary function named SICL-BOOT-PHASE2:make-instance
   ;; and that calls the function which is the value of the variable
   ;; *MAKE-INSTANCE-DEFAULT*.  The initial value of this variable is
   ;; the function SICL-BOOT-PHASE1:MAKE-INSTANCE-DEFAULT, so that
   ;; MAKE-INSTANCE creates an ersatz instance by instantiating a
   ;; bridge class.  Later, when we have ersatz classes, we change the
   ;; value of the variable to be a function that creates an ersatz
   ;; instance by instantiating an ersatz class.
   (:file "make-instance")
   (:file "make-built-in-instance")
   (:file "ensure-accessor-function")
   (:file "add-accessor-method")
   (:file "slot-definition-class-support")
   (:file "slot-definition-class-defgenerics")
   (:file "slot-definition-class-defmethods")
   (:file "validate-superclass")
   (:file "class-initialization-support")
   (:file "class-initialization-defmethods")
   (:file "generic-function-initialization-support")
   (:file "generic-function-initialization-defmethods")
   (:file "direct-slot-definition-p")
   (:file "method-initialization-support")
   (:file "method-initialization-defmethods")
   (:file "class-database")
   (:file "generic-function-database")
   (:file "class-finalization-defgenerics")
   (:file "class-finalization-support")
   (:file "class-finalization-defmethods")
   (:file "built-in-class-finalization")
   (:file "finalize-target-classes")
   (:file "patch-target-objects")
   (:file "print-object")
   (:file "satiate-all-generic-functions")
   (:file "xensure-class")
   (:file "xensure-built-in-class")
   (:file "xensure-generic-function")
   (:file "xensure-method")
   (:file "allocate-instance-support")
   (:file "allocate-instance-defuns")
   (:file "allocate-built-in-instance")
   (:file "make-instance-support")
   (:file "rename-package-2")))
