;;; evil-tex-util.el -- Functions to be used by evil-texi -*- lexical-binding: t; -*-
;;; Commentary:
;; This file is part of evil-tex, which provides license
;; information.
;;; Code:

(require 'latex)
(require 'evil-common)


(defun evil-tex-max-key (seq fn &optional compare-fn)
  "Return the element of SEQ for which FN gives the biggest result.

Comparison is done with COMPARE-FN if defined, and with `>' if not.
\(evil-tex-max-key '(1 2 -4) (lambda (x) (* x x))) => -4"
  (let* ((res (car seq))
         (res-val (funcall fn res))
         (compare-fn (or compare-fn #'>)))
    (dolist (cur (cdr seq))
      (let ((cur-val (funcall fn cur)))
        (when (funcall compare-fn cur-val res-val)
          (setq res-val cur-val
                res cur))))
    res))

(defun evil-tex--select-math (&rest args)
  "Return (beg . end) of best math match.

ARGS passed to evil-select-(paren|quote)."
  (evil-tex-max-key
   (list
    (ignore-errors (apply #'evil-select-paren
                          (regexp-quote "\\(") (regexp-quote "\\)") args))
    (ignore-errors (apply #'evil-select-paren
                          (regexp-quote "\\[") (regexp-quote "\\]") args))
    (ignore-errors (apply #'evil-select-quote ?$ args)))
   (lambda (arg) (if (and (consp arg) ; selection succeeded
                          ;; Selection is close enough to point.
                          ;; evil-select-quote can select things further down in
                          ;; the buffer.
                          (<= (- (car arg) 2) (point))
                          (>= (+ (cadr arg) 3) (point)))
                     (car arg)
                   most-negative-fixnum))))

(defun evil-tex--delim-compare (a b)
  "Recieve two cons' A B of structure (LR IA BEG END ...).
where LR is t for e.g. \\left( and nil for e.g. (,
 IA is t for -an- text objects and nil for -inner-,
BEG and END are the coordinates for the begining and end of the potential delim,
and the _'s are unimportant.
Compares between the delimiters to find which one has the largest BEG, while
making sure to choose [[\\left(]] over the \\left[[(]] delimiter evil-tex--delim finds"

  (let ((a-lr (nth 0 a))
        (b-lr (nth 0 b))
        (ia (nth 1 a))
        (a-beg (nth 2 a))
        (b-beg (nth 2 b)))
    (cond
     ((not a)                       nil)
     ((not b)                       t)
     ((and ia (not (or a-lr b-lr))) (> a-beg b-beg))
     ((and ia (and a-lr b-lr))       (> a-beg b-beg))
     ((and ia a-lr)                 (if (= (+ a-beg 5) b-beg) t   (> (+ a-beg 5) b-beg)))
     ((and ia b-lr)                 (if (= a-beg (+ b-beg 5)) nil (> a-beg (+ b-beg 5))))
     ((not (or a-lr b-lr))          (> a-beg b-beg))
     ((and a-lr b-lr)                (> a-beg b-beg))
     (a-lr                          (if (= a-beg b-beg) t (> a-beg b-beg)))
     (b-lr                          (if (= a-beg b-beg) nil (> a-beg b-beg)))
     (t                             nil))))

(defun evil-tex--delim-finder (lr deliml delimr args)
  "Return delimiter location (and more) for evil-tex--delim-finder.
LR is t for e.g. \\left( and nil for e.g. (.
DELIML and DELIMR is a string containing the non \\left part of the delimiter.
ARGS is the information about the text object needed for the functions to work,
such as wether the delimiter is an \\left( type or a ( type,
and if the text object is an -an- or an -inner-"

  (let ((delim-pair-lr (ignore-errors
                         (apply #'evil-select-paren
                                (regexp-quote (concat "\\left" deliml))
                                (regexp-quote (concat "\\right" delimr)) args)))
        (delim-pair-not-lr (ignore-errors
                             (apply #'evil-select-paren
                                    (regexp-quote deliml)
                                    (regexp-quote delimr) args))))

    (if lr ; checks if there is a delimiter of the searched type. if so returns the needed information, if not returns nil.
        (when delim-pair-lr
          (cons t (cons (car (last args))
                        delim-pair-lr)))
      (when delim-pair-not-lr
        (cons nil (cons (car (last args))
                        delim-pair-not-lr))))))

(defun evil-tex--select-delim (&rest args)
  "Return (beg . end) of closes delimiter match.

ARGS passed to evil-select-paren, within evil-tex--delim-finder."
  (cddr (evil-tex-max-key
         (list (evil-tex--delim-finder nil "(" ")" args)
               (evil-tex--delim-finder t "(" ")" args) ; when t finds \left(foo\right) instead
               (evil-tex--delim-finder nil "[" "]" args)
               (evil-tex--delim-finder t "[" "]" args)
               (evil-tex--delim-finder nil "\\{" "\\}" args)
               (evil-tex--delim-finder t "\\{" "\\}" args)
               (evil-tex--delim-finder nil "\\langle" "\\rangle" args)
               (evil-tex--delim-finder t "\\langle" "\\rangle" args))
         (lambda (arg) (when (consp arg) ; check if selection succeeded
                         arg))
         #'evil-tex--delim-compare)))

(defvar evil-tex-include-newlines-in-envs t
  "Whether to select the newlines when selecting begin/end blocks, and add newlines when surrounding with envs.")

(defun evil-tex-format-env-for-surrounding (env-name)
  "Format ENV-NAME for surrounding: return a cons of \\begin{ENV-NAME} . \end{ENV-NAME}."
  (cons (format "\\begin{%s}%s"
                env-name
                (when evil-tex-include-newlines-in-envs "\n"))
        (format "%s\\end{%s}"
                (when evil-tex-include-newlines-in-envs "\n")
                env-name)))

(defun evil-tex-format-cdlatex-accent-for-surrounding (accent)
  "Format ACCENT for surrounding: return a cons of \\ACCENT{ . }."
  (cons (concat "\\" accent "{") "}"))

(defun evil-tex-format-command-for-surrounding (command)
  "Format COMMAND for surrounding: return a cons of \\COMMAND{ . }."
  (if evil-tex--last-command-empty
      (cons (concat "\\" command "") "")
      (cons (concat "\\" command "{") "}")))

(defun evil-tex-prompt-for-env ()
  "Prompt the user for an env to insert."
  (evil-tex-format-env-for-surrounding
   (read-from-minibuffer "env: " nil minibuffer-local-ns-map)))

(defvar evil-tex--env-function-prefix "evil-tex-envs:"
  "Prefix used when generating env functions from `evil-tex-env-map-generator-alist'.")

(defvar evil-tex--cdlatex-accents-function-prefix "evil-tex-cdlatex-accents:"
  "Prefix used when generating accent functions from `evil-tex-cdlatex-accent-map-generator-alist'.")

(defvar evil-tex--delim-function-prefix "evil-tex-delims:"
  "Prefix used when generating delimiter functions from `evil-tex-delim-map-generator-alist'.")

(defun evil-tex--populate-surround-kemap (keymap generator-alist prefix
                                                 single-strings-fn)
  "Populate KEYMAP with keys and callbacks from GENERATOR-ALIST.
see `evil-tex-env-map-generator-alist' the the alist fromat.
PREFIX is the prefix to give the generated functions created
by (lambda () (interactive) (SINGLE-STRINGS-FN env)).
Return KEYMAP."

  (dolist (pair generator-alist)
    (let* ((key (car pair))
           (env (cdr pair))
           name)
      (cond
       ((stringp env)
        (setq name (intern (concat prefix env)))
        (fset name (lambda () (interactive) (funcall single-strings-fn env)))
        (define-key keymap key name))
       ((consp env)
        (setq name (intern (concat prefix (car env))))
        (fset name (lambda () (interactive) env))
        (define-key keymap key name))
       ((or (functionp env) (not env))
        (define-key keymap key env)))))
  keymap)

(defun evil-tex-read-with-keymap (keymap)
  "Prompt the user to press a key from KEYMAP.

Return the result of the called function, or error if the key
pressed isn't found."
  (let (key map-result)
    (when (require 'which-key nil t)
      (run-with-idle-timer
       which-key-idle-delay nil
       (lambda () (unless key
                    (which-key--show-keymap nil keymap nil nil t)))))
    (setq key (string (read-char)))
    (when (functionp 'which-key--hide-popup)
      (which-key--hide-popup))
    (setq map-result (lookup-key keymap key))
    (cond
     ((or (not map-result) (numberp map-result))
      (user-error "%s not found in keymap" key))
     ((functionp map-result)
      (funcall map-result))
     ((keymapp map-result)
      (evil-tex-read-with-keymap map-result)))))

;; working code courtesy of @hlissner
(defmacro evil-tex-dispatch-single-key (catch-key callback &optional fallbacks)
  "Define a an evil command to execute CALLBACK when given CATCH-KEY.

Otherwise try to call any of the functions in FALLBACKS (a
symbol) until any of them succeeds (returns non-nil.)"
  `(evil-define-command
     ,(intern (concat "evil-tex-dispath-" (string catch-key))) (count key)
     (interactive "<c><C>")
     (if (eq key ,catch-key)
         (funcall ,callback)
       (run-hook-with-args-until-success ,fallbacks
                                         count key))))

(defun evil-tex--select-command ()
  "Return command (macro) text object boundries, and emptyness status.
A command is defined to be empty if all if it's inpus have no
characters (including whitespace).

inner type text objects defined to be the entire command sans \\ if empty,
and just the input portion if non empty.

Return in format (list beg-an end-an beg-inner end-inner is-empty)"
  (let ((beg-an (TeX-find-macro-start))
        (end-an (TeX-find-macro-end))
        beg-inner end-inner (is-empty nil))
    (unless beg-an
      (user-error "No surrounding command found"))
    (save-excursion
      (goto-char beg-an)
      (unless (ignore-errors (re-search-forward "{.+}\\|\\[.+\\]" end-an))
        (setq is-empty t)))
    (save-excursion
      (goto-char beg-an)
      (ignore-errors (re-search-forward "{\\|\\[" end-an)) ;goto opeing brace if exists.
      (if (or is-empty (eq beg-an (point)))
          (setq beg-inner (1+ beg-an)) ; Set inner correctly for empty and non-empty commands.
        (setq beg-inner (point)))   ; NOTE: interprets any command with empty first input as empty.
      (save-excursion
        (goto-char end-an)
        (when (and (looking-back "}\\|\\]" (- (point) 2)) (not is-empty))
          (backward-char))
        (setq end-inner (point)) ; set end of inner to be {|} only in command is not empty
        (list beg-an end-an beg-inner end-inner is-empty)))))

(defvar evil-tex--last-command-empty nil
  "global that tells us if the last command text object used
was empty (e.g. \epsilon) or not (e.g. \dv{x})")

(defun evil-tex--select-command2 ()
  "Return command (macro) text object boundries.
inner commmand defined to be what is inside {}'s and []'s,
or empty if none exist

Return in format (list beg-an end-an beg-inner end-inner is-empty)"
  (let ((beg-an (TeX-find-macro-start))
        (end-an (TeX-find-macro-end))
        beg-inner end-inner (is-empty nil))
    (save-excursion
      (goto-char beg-an)
      (if (ignore-errors (re-search-forward "{\\|\\[" end-an))
          (setq evil-tex--last-command-empty nil)
          (setq evil-tex--last-command-empty t)))
    (unless beg-an
      (user-error "No surrounding command found"))
    (save-excursion
      (goto-char beg-an)
      (if (ignore-errors (re-search-forward "{\\|\\[" end-an))
          (setq beg-inner (point))
          (setq beg-inner end-an))) ;goto opeing brace if exists.
      (save-excursion
        (goto-char end-an)
        (when (and (looking-back "}\\|\\]" (- (point) 2)) (not is-empty))
          (backward-char))
        (setq end-inner (point)) ; set end of inner to be {|} only in command is not empty
        (list beg-an end-an beg-inner end-inner))))


(defvar evil-tex-select-newlines-with-envs t
  "Whether to select and insert newlines with env commands.

By default, the newline proceeding \\begin{...} and preceding
\\end{...} is selected as part of the delimiter. This way, when
doing =cie= you're placed on a separate line, and surrounding
with envs would force separate lines for \\begin, inner text, and
\\end.")

(defun evil-tex-env-beginning-begend ()
  "Return (start . end) of the \\begin{foo} of current env.

\\begin{equation}
^               ^"
  (let (beg)
    (save-excursion
      ;; LaTeX-find-matching-begin doesn't work if on the \begin itself
      (search-backward "\\" (line-beginning-position) t)
      (unless (looking-at (regexp-quote "\\begin{"))
        (LaTeX-find-matching-begin))
      ;; We are at backslash
      (setq beg (point))
      (skip-chars-forward "^{")        ; goto opening brace
      (forward-sexp)                   ; goto closing brace
      (when (and evil-tex-select-newlines-with-envs
                 (looking-at "\n"))
        (forward-line 1))
      (cons beg (point)))))

(defun evil-tex-env-end-begend ()
  "Return (start . end) of the \\end{foo} of current env.

\\end{equation}
^             ^"
  (let (end)
    (save-excursion
      ;; LaTeX-find-matching-end doesn't work if on the \begin itself
      (search-backward "\\" (line-beginning-position) t)
      (when (looking-at (regexp-quote "\\begin{"))
        (skip-chars-forward "^{")      ; goto opening brace
        (forward-sexp))                ; goto closing brace
      ;; Now definitely inside the env
      (LaTeX-find-matching-end)        ; we are at closing brace
      (setq end (point))
      (backward-sexp)                  ; goto opening brace
      (search-backward "\\")           ; goto backslash
      (when (and evil-tex-select-newlines-with-envs
                 (looking-back "\n" (1- (point))))
        (backward-char))
      (cons (point) end))))

(defvar evil-tex--section-regexp "\\\\\\(part\\|chapter\\|subsubsection\\|subsection\\|section\\|subparagraph\\|paragraph\\)\\*?"
  "Regexp that matches for LaTeX section commands.")

(defun evil-tex--section-regexp-higher (str)
  "For section name STR, return regex that only matche higher sections."
  (cond
   ((string-match "\\\\part\\*?" str)  "\\\\part\\*?")
   ((string-match "\\\\chapter\\*?" str)   "\\\\\\(part\\|chapter\\)\\*?")
   ((string-match "\\\\section\\*?" str)   "\\\\\\(part\\|chapter\\|section\\)\\*?")
   ((string-match "\\\\subsection\\*?" str)   "\\\\\\(part\\|chapter\\|subsection\\|section\\)\\*?")
   ((string-match "\\\\subsubsection\\*?" str)   "\\\\\\(part\\|chapter\\|subsubsection\\|subsection\\|section\\)\\*?")
   ((string-match "\\\\paragraph\\*?" str)   "\\\\\\(part\\|chapter\\|subsubsection\\|subsection\\|section\\|paragraph\\)\\*?")
   ((string-match "\\\\subparagraph\\*?" str)   "\\\\\\(part\\|chapter\\|subsubsection\\|subsection\\|section\\|subparagraph\\|paragraph\\)\\*?")))
;; (defvar evil-tex--section-regexp (concat "\\\\" (regexp-opt-group (mapcar #'car LaTeX-section-list) nil) "\\*?")

(defun evil-tex--select-section ()
  "Return begends for section text object.
an variant defined from the first character of
the \\section{} command, to the line above the next
\\section{} command of equal or higher rank,
e.g. \\chapter{}. Inner varaind starts after the
end of the command, and also after an immidiately
following newline if exists. treats \\section{} and
\\section*{} the same.
Return in format (list beg-an end-an beg-inner end-inner).


returns ((beg-an . end-an) . (beg-inner . end-inner))"
  (let (beg-an end-an beg-inner end-inner what-section)
    (save-excursion
      ;; back searching won't work if we are on the \section itself
      (search-backward "\\" (line-beginning-position) t)
      (if (looking-at evil-tex--section-regexp)
          (setq what-section (match-string 0))
        (re-search-backward evil-tex--section-regexp)
        (setq what-section (match-string 0)))
      ;; We are at backslash
      (setq beg-an (point))
      (skip-chars-forward "^{")        ; goto opening brace
      (forward-sexp)                   ; goto closing brace
      (when (and evil-tex-select-newlines-with-envs
                 (looking-at "\n"))
        (forward-line 1))
      (setq beg-inner (point))
      (re-search-forward (concat (evil-tex--section-regexp-higher what-section) "\\|\\\\end{document}"))
      (move-beginning-of-line 1)
      (setq end-inner (point))
      (setq end-an (point))
      (list beg-an end-an beg-inner end-inner))))

(defun evil-tex--goto-script-prefix (subsup)
  "Return goto end of the found SUBSUP prefix.
{(ab|)}_c => {(ab)}_|c"
  (let ((orig-point (point))
        subsup-end)
    (or
     ;; subsup after point
     (when (search-forward subsup (line-end-position 2) t) ; 2 lines down
       (let (beg end)
         (setq subsup-end (match-end 0))
         (goto-char (match-beginning 0))
         (setq end (point))
         (when
             (cond
              ;; {}^
              ((eq (char-before) ?})
               (backward-sexp)
               (setq beg (point)))
              ;; \command^
              ((and (search-backward "\\" (line-beginning-position) t)
                    (looking-at "\\\\[A-Za-z@*]+")
                    (eq end (match-end 0)))
               (setq beg (match-beginning 0)))
              ;; a^
              (t
               (setq beg (1- (point)))))
           ;; require point to be inside the base bounds
           (<= beg orig-point end))))
     ;; subsup before point
     (when (search-backward subsup (line-beginning-position 0))
       (setq subsup-end (match-end 0)))
     (user-error "No surrounding %s found" subsup))
    (goto-char subsup-end)))

(defun evil-tex-script-beginning-begend (subsup)
  "Return (start . end) of the sub/superscript that point is in.
SUBSUP should be either \"^\" or \"_\"

a_{n+1}
 ^^"
  (let (start)
    (save-excursion
      (evil-tex--goto-script-prefix subsup)
      (setq start (1- (point)))
      (when (looking-at "{") ; select brace if present
        (forward-char 1))
      (cons start (point)))))

(defun evil-tex-script-end-begend (subsup)
  "Return (start . end) of the sub/superscript that point is in.
SUBSUP should be either \"^\" or \"_\"

a_{n+1}
      ^"
  (save-excursion
    (evil-tex--goto-script-prefix subsup)
    (cond
     ;; a_{something}
     ((looking-at "{")
      (forward-sexp)
      (cons (1- (point)) (point)))
     ;; a_\something
     ((looking-at "\\\\[a-zA-Z@*]+")
      (goto-char (match-end 0))
      ;; skip command arguments
      (while (looking-at "{\\|\\[")
        (forward-sexp))
      (cons (point) (point)))
     (t ;; a_1 a_n
      (forward-char)
      (cons (point) (point))))))

(defun evil-tex--regexp-overlay-replace (deliml delimr an-over in-over)
  "Replace surround area with new delimiters.
Take the surround area defined by overlays AN-OVER and IN-OVER,
delete the parts of AN-OVER that don't overlap with IN-OVER, and surround
the remaining IN-OVER with new delimiters DELIML and DELIMR.
Should be used inside of a 'save-excursion'."
  (progn (delete-region (overlay-start an-over) (overlay-start in-over))
         (goto-char (overlay-start an-over))
         (insert deliml)
         (delete-region (overlay-end in-over) (overlay-end an-over))
         (goto-char (overlay-end in-over))
         (insert delimr)))

(defun evil-tex-toggle-delim ()
  "Toggle surrounding delimiters between e.g. (foo) and \\left(foo\\right) ."
  (let ((an-over (make-overlay (car (evil-tex-a-delim)) (cadr (evil-tex-a-delim))))
        (in-over (make-overlay (car (evil-tex-inner-delim)) (cadr (evil-tex-inner-delim)))))
    (save-excursion
      (goto-char (overlay-start an-over))
      (cl-destructuring-bind (l . r)
          (cond
           ((looking-at (regexp-quote "("))
            '("\\left(" . "\\right)"))
           ((looking-at (regexp-quote "\\left("))
            '("(" . ")"))
           ((looking-at (regexp-quote "["))
            '("\\left[" . "\\right]"))
           ((looking-at (regexp-quote "\\left["))
            '("[" . "]"))
           ((looking-at (regexp-quote "\\{"))
            '("\\left\\{" . "\\right\\}"))
           ((looking-at (regexp-quote "\\left\\{"))
            '("\\{" . "\\}"))
           ((looking-at (regexp-quote "\\langle"))
            '("\\left\\langle" . "\\right\\rangle"))
           ((looking-at (regexp-quote "\\left\\langle"))
            '("\\langle" . "\\rangle"))
           (t
            (user-error "No surrounding delimiter found")))
        (evil-tex--regexp-overlay-replace l r an-over in-over)))
    (delete-overlay an-over) (delete-overlay in-over)))

(defun evil-tex-toggle-env ()
  "Toggle surrounding enviornments between e.g. \\begin{equation} and \\begin{equation*}."
  (let ((an-over (make-overlay (car (evil-tex-an-env)) (cadr (evil-tex-an-env))))
        (in-over (make-overlay (car (evil-tex-inner-env)) (cadr (evil-tex-inner-env)))))
    (save-excursion
      (goto-char (overlay-start an-over))
      (skip-chars-forward "^}")
      (backward-char 1)
      (if (eq ?* (char-after)) (delete-char 1) (progn (forward-char 1) (insert-char ?*)))
      (goto-char (overlay-end in-over))
      (skip-chars-forward "^}")
      (backward-char 1)
      (if (eq ?* (char-after)) (delete-char 1) (progn (forward-char 1) (insert-char ?*))))
    (delete-overlay an-over) (delete-overlay in-over)))

(defun evil-tex-toggle-math ()
  "Toggle surrounding math between \\(foo\\) and \\[foo\\]."
  (let ((an-over (make-overlay (car (evil-tex-a-math)) (cadr (evil-tex-a-math))))
        (in-over (make-overlay (car (evil-tex-inner-math)) (cadr (evil-tex-inner-math)))))
    (save-excursion
      (goto-char (overlay-start an-over))
      (cond
       ((looking-at (regexp-quote "\\("))
        (evil-tex--regexp-overlay-replace "\\[" "\\]" an-over in-over))
       ((looking-at (regexp-quote "\\["))
        (evil-tex--regexp-overlay-replace "\\(" "\\)" an-over in-over))))
    (delete-overlay an-over) (delete-overlay in-over)))

(defun evil-tex-toggle-command ()
  "Toggle surrounding enviornments between e.g. \\begin{equation} and \\begin{equation*}."
  (let ((an-over (make-overlay (car (evil-tex-a-command)) (cadr (evil-tex-a-command))))
        (in-over (make-overlay (car (evil-tex-inner-command)) (cadr (evil-tex-inner-command)))))
    (save-excursion
      (goto-char (overlay-start an-over))
      (skip-chars-forward "^{")
      (backward-char 1)
      (if (eq ?* (char-after)) (delete-char 1) (progn (forward-char 1) (insert-char ?*))))
    (delete-overlay an-over) (delete-overlay in-over)))

(defun evil-tex-toggle-section ()
  "Toggle surrounding enviornments between e.g. \\begin{equation} and \\begin{equation*}."
  (let ((an-over (make-overlay (car (evil-tex-a-section)) (cadr (evil-tex-a-section))))
        (in-over (make-overlay (car (evil-tex-inner-section)) (cadr (evil-tex-inner-section)))))
    (save-excursion
      (goto-char (overlay-start an-over))
      (skip-chars-forward "^{")
      (backward-char 1)
      (if (eq ?* (char-after)) (delete-char 1) (progn (forward-char 1) (insert-char ?*))))
    (delete-overlay an-over) (delete-overlay in-over)))


(provide 'evil-tex-util)
;;; evil-tex-util.el ends here