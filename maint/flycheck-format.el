;;; flycheck-format.el --- Flycheck: Source code formatter  -*- lexical-binding: t; -*-

;; Copyright (C) 2016, 2018  Sebastian Wiesner and Flycheck contributors

;; Author: Sebastian Wiesner <swiesner@lunaryorn.com>
;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file provides source code formatting for Flycheck.  It's mainly intended
;; for non-interactive use, see "make format".

;;; Code:

(unless (version<= "25" emacs-version)
  (user-error "Emacs 25 required for formatting"))

(require 'seq)
(require 'rx)
(require 'f)
(require 'whitespace)
(require 'elisp-mode)

(require 'flycheck-maint
         (expand-file-name "flycheck-maint"
                           (file-name-directory (f-this-file))))

(defun flycheck/eval-and-format-buffer (filename)
  "Format the current buffer for FILENAME.

THIS FUNCTION HAS GLOBAL AND LOCAL SIDE EFFECTS.

Evaluate the buffer to make all special indentation rules of
local definitions available before formatting.

Switch the buffer to Emacs Lisp mode."
  (let (delayed-mode-hooks)
    (delay-mode-hooks (emacs-lisp-mode)))
  ;; Load the file to make indentation rules from local definitions available.
  ;; We load files instead of evaluating them because some files in our code
  ;; rely on `load-file-name' and similar stuff.  Don't load files which are
  ;; already loaded, though, to prevent a recursive load of this file.
  (unless (flycheck/already-loaded-p filename)
    (let ((load-prefer-newer t))          ; Silence "newer" messages
      (load filename 'noerror 'nomessage 'nosuffix)))
  (widen)
  (let ((indent-tabs-mode nil)
        (whitespace-style
         '(empty                        ; Cleanup empty lines at end
           indentation::space           ; Replace tabs with spaces
           space-before-tab::space      ; Replace tabs with spaces
           trailing                     ; Remove trailing spaces
           )))
    (let ((inhibit-message t))
      ;; Silence "Indenting region..." progress reporter
      (indent-region (point-min) (point-max)))
    (whitespace-cleanup-region (point-min) (point-max))))

(defun flycheck/check-long-lines (filename &optional length)
  "Check buffer for long lines.

FILENAME is the name of the file being checked.

Display a message for any line longer than LENGTH.  If LENGTH is
not specified, defaults to `fill-column'.  If the buffer has no
long lines return t, otherwise return nil.

The first line of the buffer is allowed"
  (let ((long-lines 0)
        (max-length (or length fill-column)))
    (save-excursion
      (goto-char (point-min))
      ;; The first line is allowed to be any length
      (forward-line 1)
      (while (not (eobp))
        (end-of-line)
        (when (> (current-column) max-length)
          (message "%s:%d: line is over %d characters"
                   filename
                   (line-number-at-pos (point))
                   max-length)
          (setq long-lines (1+ long-lines)))
        (forward-line 1)))
    (= long-lines 0)))

(defun flycheck/file-formatted-p (filename)
  "Check whether FILENAME is properly formatted.

Return a non-nil value in this case, otherwise return nil."
  (with-temp-buffer
    (insert-file-contents filename)
    (set-buffer-modified-p nil)
    (flycheck/eval-and-format-buffer filename)
    (and (not (buffer-modified-p))
         (flycheck/check-long-lines filename 80))))

(defun flycheck/batch-check-format ()
  "Check formatting of all sources."
  (let ((bad-files (seq-remove #'flycheck/file-formatted-p
                               (flycheck/all-source-files))))
    (if (null bad-files)
        (kill-emacs 0)
      (seq-do (lambda (filename) (message "%s: misformatted!" filename))
              bad-files)
      (kill-emacs 1))))

(defun flycheck/format-file (filename)
  "Format FILENAME.

Return a non-nil value if the file was formatted, and nil
otherwise."
  (with-temp-file filename
    (insert-file-contents filename)
    (set-buffer-modified-p nil)
    (flycheck/eval-and-format-buffer filename)
    (buffer-modified-p)))

(defun flycheck/batch-format ()
  "Format all Flycheck source files."
  (let ((formatted-files (seq-filter #'flycheck/format-file
                                     (flycheck/all-source-files))))
    (seq-do (lambda (filename) (message "Formatted %s" filename))
            formatted-files)
    (kill-emacs 0)))

;;; flycheck-format.el ends here
