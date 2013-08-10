(in-package #:site-generator)
;;;; ## Templates
(export
 '(*template-delimiter*
   *delimiter-escape*
   with-env
   expand
   expand-string-to-string))

(defvar *template-delimiter* #\$
  "The character that indicates that a template expansion is to take place. If a variable is being expended, an extra delimiter must follow immediately after e.g. *foo*, otherwise the expression following the delimiter should begin with an open paren and be READable.")

(defvar *delimiter-escape* #\\
  "The character that indicates that a *TEMPLATE-DELIMITER* should be escaped. This will also escape other *DELIMITER-ESCAPE* characters but only when immediately preceding a *TEMPLATE-DELIMITER*.")

(defmacro with-env ((env &key (use '(:cl :iterate :site-generator))) &body body)
  "Evaluate the BODY in a new anonymous package, using USE and filled with values associated with the the non-keyworded symbols in the plist ENV. For instance, when env is '(:foo 'bar), the symbol FOO in this new package is set to 'BAR."
  `(let ((*package* (defpackage ,(gensym) ,(cons :use use))))
     (iter (for (var value) on ,env by #'cddr)
	   (setf (symbol-value (intern (symbol-name var))) value))
     ,@body
     (delete-package *package*)))

(defun expand (input &key (output *standard-output*))
  "stream (:output stream) -> IO

Copy INPUT to OUTPUT while expanding any template variables or expressions (as delimited by *TEMPLATE-DELIMITER* and *DELIMITER-ESCAPE*).

The evaluation of any expression to be expanded takes place in *PACKAGE*, which can be set to reflect a particular environment with WITH-ENV."
  (iter (for c = (read-char input nil 'eof))
	(until (eq c 'eof))
	(cond
	  ((char= c *delimiter-escape*)
	   (escape-chars input output))
	  ((char= c *template-delimiter*)
	   (expand-template input output))
	  (t (write-char c output)))))

(defun expand-string-to-string (input)
  "string -> string

Like EXPAND, but inputs and outputs strings."
  (with-input-from-string (in input)
    (with-output-to-string (out)
      (expand in :output out))))

;;;; ### Private
(defun escape-chars (input output)
  "stream stream -> IO

Determine what characters need to be escaped, and print them to OUTPUT. The INPUT stream is positioned immediately after a *DELIMITER-ESCAPE* character.

Only *TEMPLATE-DELIMITER* characters need to be escaped, so if, after the escape character there is not a template delimiter, possibly preceeded by more escape characters, but with nothing in between, then this function should print anything read to OUTPUT, unmodified.

Other *DELIMITER-ESCAPE* characters may appear before the *TEMPLATE-DELIMITER* character, in which case, they can also be escaped. In general, an even number of *DELIMITER-ESCAPE* characters means that only the escape characters themselves are being escaped, while an odd number means that the template character is being escaped.
"
  (let* ((read (list *delimiter-escape*))
	 (escapers 1)
	 (out (iter (for c = (read-char input nil 'eof))
		    (if (eq c 'eof)
			(return read)
			(push c read))
		    (cond
		      ((char= c *delimiter-escape*)
		       (incf escapers))
		      ((char= c *template-delimiter*)
		       (return (if (oddp escapers)
				   ; Template escaped: return number of unescaped escape characters, plus a template delimeter
				   (cons *template-delimiter*
					 (times (floor escapers 2) *delimiter-escape*))
				   (progn
				   ; Template unescaped: return number of unescaped escape characters, and unread template delimeter
				     (unread-char *template-delimiter* input)
				     (times (floor escapers 2) *delimiter-escape*)))))
		      (t (return read))))))
    (iter (for c in (reverse out))
	  (write-char c output))))

(defun expand-template (input output)
  "stream stream -> IO

The INPUT stream is positioned immediately after a *TEMPLATE-DELIMITER* character and should expand the template into OUTPUT if such template exists.

If the next character in INPUT is non-existant, whitespace, or a digit, the *TEMPLATE-DELIMITER* was not actually indicating the presense of a template, and so the delimiter should be written into OUTPUT.

If the following character in INPUT is #\(, it is assumed to belong to a READable expression. 

If the following character in INPUT is anything else, it may be the start of a variable. If none of the characters until the next *TEMPLATE-DELIMITER* are whitespace, then it is assumed to be a variable and expanded. If whitespace is present, the characters that were read from INPUT should be printed to OUTPUT.
"
  (let+ ((peek (peek-char nil input nil 'eof))
	 (read-in (list *template-delimiter*))
	 ((&flet backtrack ()
	    (iter (for c in (reverse read-in))
		  (write-char c output))
	    (return-from expand-template)))
	 ((&flet next-char ()
	    (let ((c (read-char input nil 'eof)))
	      (unless (eq c 'eof)
		(push c read-in))
	      c)))
	 ((&flet expand-variable-or-backtrack ()
	    (iter (for c = (next-char))
		  (cond
		    ((or (whitespace-char-p c)
			 (eq c 'eof))
		     (backtrack))
		    ((char= c *template-delimiter*)
		     (return (intern (string-upcase
				      (concatenate
				       'string (cdr (reverse (cdr read-in)))))))))))))
    (cond ((or (eq peek 'eof)
	       (whitespace-char-p peek)
	       (digit-char-p peek))
	   (backtrack))
	  ((char= peek #\()
	   (expand-expression (read input) output))
	  (t (expand-expression (expand-variable-or-backtrack) output)))))

(defun expand-expression (expr output)
  "expr stream -> IO

Print the evaluationof the expression EXPR, aesthetically, to OUTPUT. If EXPR evaluates to a list it is assumed to be a list of strings, which will be concatenated."
  (let ((e (eval expr)))
    (format output "~a" (if (listp e)
			    (concatenate 'string (flatten e))
			    e))))

;;;; ### Util
(defun times (n elt)
  "natural x -> (x)

Return a list of n ELTs."
  (iter (for x from 0 below n)
	(collect elt)))

(defun whitespace-char-p (char)
  "character -> boolean

Return true if CHAR is a whitespace character."
  (if (find char '(#\Space #\Newline #\Tab) :test #'char=)
      t))

