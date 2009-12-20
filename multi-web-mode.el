;;; multi-web-mode.el --- multiple major mode support for web editing

;; Copyright (C) 2009 Fabián Ezequiel Gallina.

;; Author: Fabián Ezequiel Gallina <fabian@gnu.org.ar>
;; Maintainer: Fabián Ezequiel Gallina <fabian@gnu.org.ar>
;; Keywords: convenience, languages, wp

;; This file is part of Multi Web Mode

;; Multi Web Mode is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; Multi Web Mode is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with Multi Web Mode. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Multi Web Mode is a minor mode wich makes web editing in Emacs much easier.

;; Basically what it does is select the appropiate major mode
;; automatically when you move the point and also calculates the
;; correct indentation of chunks according to the indentation of the
;; most relevant major mode.

;;

;;; Code:


(defvar mweb-mode-map
  (let ((mweb-mode-map (make-sparse-keymap)))
    (define-key mweb-mode-map (kbd "M-<f11>") 'mweb-set-default-major-mode)
    (define-key mweb-mode-map (kbd "M-<f12>") 'mweb-set-extra-indentation)
    mweb-mode-map)
  "Keymaps for multi-web-mode")


(defvar mweb-mode-hook nil
  "Hooks to run when multi-web-mode is initialized")


(defvar mweb-extra-indentation 0
  "Extra indentation for chunks, automatically calculated when
the major mode has changed")


(defcustom mweb-default-major-mode 'html-mode
  "*Default major mode when not in chunk"
  :type 'symbol
  :group 'multi-web-mode)


(defcustom mweb-filename-extensions
  '("php" "htm" "html" "ctp" "phtml" "php4" "php5")
  "*Filename extensions on which multi-web-mode should
auto-activate"
  :type '(list string)
  :group 'multi-web-mode)


(defcustom mweb-tags
  '(("<\\?php\\|<\\? \\|<\\?=" "\\?>" php-mode)
    ("<script +\\(type=\"text/javascript\"\\|language=\"javascript\"\\)[^>]*>" 
     "</script>" espresso-mode)
    ("<style +type=\"text/css\"[^>]*>" "</style>" css-mode))
  "*Tags enabled for multi-web-mode. This var is an alist on which
each element has the form (\"open tag regex\" \"close tag
regex\" major-mode"
  :type '(repeat (string string symbol))
  :group 'multi-web-mode)


(defcustom mweb-submode-indent-offset 2
  "*Indentation offset for code inside chunks."
  :type 'integer
  :group 'multi-web-mode)


(defcustom mweb-ignored-commands
  (list
   'undo
   'yas/expand
   'yas/next-field-or-maybe-expand
   'isearch-forward
   'isearch-backward
   'isearch-other-control-char)
  "*List of commands that will prevent multi-web-mode to change
the mayor mode."
  :type '(repeat symbol)
  :group 'multi-web-mode)


(defun mweb--tag-get-attr (tag attribute)
  "Gets ATTRIBUTE from TAG. 

ATTRIBUTE values can be 'mode to get the tag's major mode or
'open/'close to get the open/close regexp respectively."
  (cond ((equal attribute 'open)
         (car tag))
        ((equal attribute 'close)
         (cadr tag))
        ((equal attribute 'mode)
         (caddr tag))))


(defun mweb--get-tag (tag-major-mode)
  "Returns a tag from `mweb-tags' matching MAJOR-MODE."
  (catch 'break
    (dolist (tag mweb-tags)
      (when (equal (mweb--tag-get-attr tag 'mode) tag-major-mode)
        (throw 'break tag)))))


(defun mweb-change-major-mode ()
  "Calls the appropiate major mode for the pointed chunk. If the
current major-mode is the correct one it doesn't funcall the
major mode and returns nil, otherwise changes the major-mode and
returns a symbol with its name."
  (interactive)
  (let ((closest-chunk-point 0)
        (closest-chunk-mode mweb-default-major-mode)
        (result nil))
    (save-restriction
      (widen)
      (dolist (tag mweb-tags)
        (setq result (mweb-closest-starting-chunk-point tag))
        (when (and (integerp result)
                   (<= closest-chunk-point result))
          (setq closest-chunk-point result)
          (setq closest-chunk-mode (mweb--tag-get-attr tag 'mode)))))
      (when (not (equal closest-chunk-mode major-mode))
        (funcall closest-chunk-mode)
        closest-chunk-mode)))


(defun mweb-change-indent-line-function ()
  "Sets the correct value for `indent-line-function' and
`indent-region-function' depending of `major-mode'."
  (when (not (equal major-mode mweb-default-major-mode))
    (set (make-local-variable 'indent-line-function) 'mweb-indent-line)))


(defun mweb-closest-starting-chunk-point (tag)
  "Returns the point of the closest chunk for TAG which is one of
the tag contained in the `mweb-tags' list. If the chunk is not
found then it returns nil."
  (let ((open-tag)
        (close-tag))
  (save-excursion
    (setq open-tag (re-search-backward (mweb--tag-get-attr tag 'open) nil t)))
  (save-excursion
    (setq close-tag (re-search-backward (mweb--tag-get-attr tag 'close) nil t)))
  (cond ((not open-tag)
         nil)
        ((and open-tag
              (not close-tag))
         open-tag)
        ((> open-tag close-tag)
         open-tag))))


(defun mweb-update-context ()
  "This function takes care of updating the extra indentation for
chunks."
  (let ((changed-major-mode (mweb-change-major-mode)))
    (if (and changed-major-mode
             (not (equal major-mode mweb-default-major-mode)))
        (setq mweb-extra-indentation (mweb-calculate-indentation))
      (setq mweb-extra-indentation 0)))
  (mweb-change-indent-line-function))


(defun mweb-calculate-indentation ()
  "Helper used to calculate the correct indentation taking into
account the previous submode"
  (interactive)
  (let ((indentation 0)
        (eol)
        (changed-major-mode major-mode)
        (buffer-modified-flag (buffer-modified-p)))
    (save-excursion
      (mweb-goto-current-mode-open-tag)
      (forward-line -1)
      (end-of-line)
      (insert "\n")
      (insert "a")
      (mweb-change-major-mode)
      (when (equal major-mode mweb-default-major-mode)
        (indent-according-to-mode))
      (setq indentation (current-indentation))
      (end-of-line)
      (setq eol (point-marker))
      (beginning-of-line)
      (delete-region (point-marker) eol)
      (delete-backward-char 1))
    (funcall changed-major-mode)
    (set-buffer-modified-p buffer-modified-flag)
    indentation))


(defun mweb-submode-indent-line ()
  "Function to use when indenting a submode line"
  (interactive)
  (if (not (mweb-looking-at-open-tag-p))
      (if (not (mweb-looking-at-close-tag-p))
          (save-excursion
            (beginning-of-line)
            (delete-horizontal-space)
            (indent-according-to-mode)
            (indent-to (+ mweb-extra-indentation mweb-submode-indent-offset)))
        (let ((open-tag-indentation 0))
          (save-excursion
            (mweb-goto-current-mode-open-tag)
            (setq open-tag-indentation (current-indentation)))
          (beginning-of-line)
          (delete-horizontal-space)
          (indent-to open-tag-indentation)))
    (progn
      (beginning-of-line)
      (delete-horizontal-space)
      (insert "a")
      (delete-horizontal-space)
      (beginning-of-line)
      (mweb-update-context)
      (indent-according-to-mode)
      (indent-to (+ mweb-extra-indentation mweb-submode-indent-offset))
      (delete-char 1))))


(defun mweb-indent-region (start end)
  "Indents a region taking into account the relative position of
the chunks within the buffer.

It follows the same filosophy than `mweb-indent-line-forward'
because that function is what is used to indent the chunks
which are not for the default major mode."
  (interactive "r")
  (let ((line-end))
    (save-excursion
      (goto-char end)
      (setq end (point-marker))
      (goto-char start)
      (or (bolp) (forward-line 1))
      (while (< (point) end)
        (mweb-update-context)
        (mweb-indent-line)
        (forward-line 1))
      (move-marker end nil))))


(defun mweb-get-current-mode-tag-point (type)
  "Gets the point marker of current chunk's open/close tag.

The TYPE argument can be a 'open for the open tag or 'close for
the close tag."
  (when (not (equal major-mode mweb-default-major-mode))
    (let ((index 0)
          (found nil)
          (tag)
          (result nil)
          (re-search-func (if (equal type 'open)
                              're-search-backward
                            're-search-forward)))
      (while (and (< index (length mweb-tags))
                  (not found))
        (setq tag (elt mweb-tags index))
        (when (or (equal (mweb--tag-get-attr tag 'mode) major-mode)
                  (equal major-mode mweb-default-major-mode))
          (setq found t)
          (save-excursion
            (if (looking-at (mweb--tag-get-attr tag type))
                (progn
                  (back-to-indentation)
                  (setq result (point)))
              (while
                  (progn
                    (setq result (funcall re-search-func (mweb--tag-get-attr tag type) nil t))
                    (and (not (equal result nil))
                         (mweb-point-at-comment)))))))
        (setq index (+ 1 index)))
      result)))


(defun mweb-goto-current-mode-open-tag ()
  "Moves the point to the open tag of the current chunk"
  (interactive)
  (let ((tag-point (mweb-get-current-mode-tag-point 'open)))
    (when tag-point
      (goto-char tag-point))))


(defun mweb-goto-current-mode-close-tag ()
  "Moves the point to the close tag of the current chunk"
  (interactive)
  (let ((tag-point (mweb-get-current-mode-tag-point 'close)))
    (when tag-point
      (goto-char tag-point))))


(defun mweb-set-extra-indentation (number)
  "Sets the new value for `mweb-extra-indentation' to NUMBER"
  (interactive "nNew mweb-extra-indentation value: ")
  (setq mweb-extra-indentation number)
  (message "mweb-extra-indentation = %d" mweb-extra-indentation))


(defun mweb-set-default-major-mode (major-mode)
  "Sets the new value for `mweb-default-major-mode' to MAJOR-MODE"
  (interactive "CNew default major mode: ")
  (setq mweb-default-major-mode major-mode)
  (mweb-change-major-mode)
  (message "mweb-default-major-mode = %s" mweb-default-major-mode))


(defun mweb-point-at-comment ()
  "Returns if the point is in a comment. To test this we check if
the face-at-point is equal to 'font-lock-comment-face"
  (interactive)
  (let ((point (point-marker)))
    (if (equal (face-at-point) 'font-lock-comment-face)
        t
      nil)))


(defun mweb-forward-nonblank-line (&optional number)
  "Moves the cursor to the next/previous non blank line.

When NUMBER is positive it moves forward and when is negative
it moves backwards."
  (when (not number)
    (setq number 1))
  (when (> number 1)
    (setq number 1))
  (when (< number -1)
    (setq number -1))
  (forward-line number)
  (while (and (equal (mweb-get-current-line-trimmed-contents) "")
              (not (eobp)))
    (forward-line number)))


(defun mweb-get-current-line-trimmed-contents ()
  "Gets the contents of the current line. It trims all space
characters at the beginning and end of the line."
  (let ((start-point)
        (end-point)
        (contents))
    (save-excursion
      (beginning-of-line)
      (setq start-point (point))
      (end-of-line)
      (setq end-point (point))
      (setq contents (buffer-substring start-point end-point))
      (when (string-match "[ \t]*$" contents)
        (setq contents (replace-match "" nil nil contents)))
      (when (string-match "^[ \t]*" contents)
        (setq contents (replace-match "" nil nil contents))))
    contents))


(defun mweb-looking-at-tag (&optional type)
  "Returns non-nil if pointer is looking at an open or close tag.

Possible values of TYPE are:
    * nil: to check if point is looking at an open or close tag.
    * 'open: to check if point is looking at an open tag
    * 'close: to check if point is looking at a close tag
"
  (let ((index 0)
        (looking)
        (open-tag)
        (close-tag)
        (tag-regexp))
    (save-excursion
      (back-to-indentation)
      (while (and (< index (length mweb-tags))
                  (not looking))
        (setq open-tag (mweb--tag-get-attr (elt mweb-tags index) 'open))
        (setq close-tag (mweb--tag-get-attr (elt mweb-tags index) 'close))
        (case type
          ('nil (setq tag-regexp (concat open-tag "\\|" close-tag)))
          ('open (setq tag-regexp open-tag))
          ('close (setq tag-regexp close-tag)))
        (when (looking-at tag-regexp)
          (setq looking t))
        (setq index (+ 1 index))))
    looking))


(defsubst mweb-looking-at-open-tag-p ()
  "Returns t if point is looking at an open tag"
  (mweb-looking-at-tag 'open))


(defsubst mweb-looking-at-close-tag-p ()
  "Returns t if point is looking at a close tag"
  (mweb-looking-at-tag 'close))


(defsubst mweb-looking-at-tag-p ()
  "Returns t if point is looking at an open or close tag"
  (mweb-looking-at-tag))


(defun mweb-post-command-hook ()
  "The function which is appended to the `post-command-hook'"
  (when multi-web-mode
    (set (make-local-variable 'indent-region-function) 'mweb-indent-region)
    (when (and (not (region-active-p))
               (not (member last-command mweb-ignored-commands)))
      (mweb-update-context))))


(defun mweb-enable ()
  "Initializes the minor mode"
  (setq mweb-is-disabled nil)
  (add-hook 'post-command-hook 'mweb-post-command-hook)
  (assq-delete-all 'multi-web-mode minor-mode-map-alist)
  (push (cons 'multi-web-mode mweb-mode-map) minor-mode-map-alist)
  (run-hooks 'mweb-mode-hook))


(defun mweb-disable ()
  "Contains the necessary code to disable the minor mode"
  (assq-delete-all 'multi-web-mode minor-mode-map-alist))


;;;###autoload
(define-minor-mode multi-web-mode
  "Enables the multi web mode chunk detection and indentation"
  :lighter " Multi-Web" :group 'convenience
  (if multi-web-mode
      (mweb-enable)
    (mweb-disable)))


(defun multi-web-mode-maybe ()
  "Used to turn on the globalized minor mode."
  (when (member 
         (file-name-extension (or buffer-file-name "")) 
         mweb-filename-extensions)
    (multi-web-mode 1)))


(define-globalized-minor-mode multi-web-global-mode
  multi-web-mode multi-web-mode-maybe
  :group 'multi-web-mode
  :require 'multi-web-mode)


(provide 'multi-web-mode)

;;; multi-web-mode.el ends here