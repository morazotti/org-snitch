;;; org-snitch.el --- Project-specific org-capture and link faces -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Nícolas Morazotti

;; Author: Nícolas Morazotti <nicolas.morazotti@gmail.com>
;; Maintainer: Nícolas Morazotti <nicolas.morazotti@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: org, project, outlines
;; URL: https://github.com/morazotti/org-snitch

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides project-specific org-capture utilizing project.el.
;; Similar to tsod's snitch library written in Go.

;;; Code:

(require 'org)
(require 'org-capture)
(require 'project)
(require 'rx)

(defgroup org-snitch nil
  "Project-specific org-capture and link faces."
  :group 'org)

(defcustom org-snitch-target-file "project.org"
  "Default Org file where project information and tracking are stored.
Relative to project root."
  :type 'file
  :group 'org-snitch)

(defcustom org-snitch-capture-key "p"
  "Key used for the main project capture template."
  :type 'string
  :group 'org-snitch)

(defcustom org-snitch-capture-templates
  '(("t" . "Tasks")
    ("n" . "Notes")
    ("i" . "Issues"))
  "List of sub-templates for project capture.
Each element is a cons cell (KEY . DESCRIPTION)."
  :type '(alist :key-type string :value-type string)
  :group 'org-snitch)

(defcustom org-snitch-independent-submodules t
  "If non-nil, treat git submodules as independent projects.
This ensures `project.org` is kept inside the submodule rather
than the parent project.  Internally, this let-binds
`project-vc-merge-submodules' to nil during project discovery."
  :type 'boolean
  :group 'org-snitch)

(defun org-snitch--get-project-root ()
  "Find the project root, respecting `org-snitch-independent-submodules'."
  (require 'project)
  (let ((project-vc-merge-submodules (not org-snitch-independent-submodules)))
    (if-let ((project (project-current)))
        (if (fboundp 'project-root)
            (project-root project)
          (cdr project))
      (user-error "Not inside a project!"))))

(defun org-snitch-context-p ()
  "Return non-nil if inside a project.  Used for capture context."
  (ignore-errors (org-snitch--get-project-root)))

(defun org-snitch--generated-templates ()
  "Generate `org-capture-templates' entries for org-snitch."
  (cons `(,org-snitch-capture-key "Project")
        (mapcar (lambda (tpl)
                  (let ((key (car tpl))
                        (desc (cdr tpl)))
                    `(,(concat org-snitch-capture-key key) ,desc entry
                      (file+headline org-snitch-find-project-file ,desc)
                      "* TODO %<%Y%m%d%H%M%S> %?%i \n"
                      :after-finalize (lambda ()
                                        (org-snitch-set-id-from-heading)
                                        (org-snitch-insert-link)
                                        (org-snitch-update-id-locations)))))
                org-snitch-capture-templates)))

(defun org-snitch--generated-contexts ()
  "Generate `org-capture-templates-contexts' entries for org-snitch."
  (cons `(,org-snitch-capture-key (org-snitch-context-p))
        (mapcar (lambda (tpl)
                  `(,(concat org-snitch-capture-key (car tpl)) (org-snitch-context-p)))
                org-snitch-capture-templates)))

;;;###autoload
(defun org-snitch-setup ()
  "Add `org-snitch' capture templates and contexts to `org-capture'."
  (interactive)
  (require 'org-capture)
  (unless (boundp 'org-capture-templates-contexts)
    (setq org-capture-templates-contexts nil))
  (let ((keys (cons org-snitch-capture-key
                    (mapcar (lambda (tpl) (concat org-snitch-capture-key (car tpl)))
                            org-snitch-capture-templates))))
    (setq org-capture-templates
          (seq-remove (lambda (x) (member (car x) keys)) org-capture-templates))
    (setq org-capture-templates-contexts
          (seq-remove (lambda (x) (member (car x) keys)) org-capture-templates-contexts)))
  (setq org-capture-templates (append org-capture-templates (org-snitch--generated-templates)))
  (setq org-capture-templates-contexts (append org-capture-templates-contexts (org-snitch--generated-contexts))))

(defvar org-snitch--source-buffer nil
  "Buffer where `org-capture' was invoked.")
(defvar org-snitch--region-beg-marker nil
  "Marker storing the start of the active region before capture.")
(defvar org-snitch--region-end-marker nil
  "Marker storing the end of the active region before capture.")
(defvar org-snitch--key nil
  "The template key used for the current capture.")

(defvar org-snitch-link-overlay-regexp
  (rx "[[" (one-or-more (not "]")) "][" (group (one-or-more (not "]"))) "]]")
  "Regular expression for matching simple bracket links `[[id:hash][desc]]'.")

(defface org-snitch-link-face
  '((t :foreground "orange"
       :weight light
       :underline t))
  "Face for org links rendered in non-org buffers."
  :group 'org-snitch)

(defun org-snitch--make-overlays ()
  "Create visual overlays for `org-mode' links in the current buffer.
Matches `org-snitch-link-overlay-regexp' and applies `org-snitch-link-face'."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward org-snitch-link-overlay-regexp nil t)
      (let ((ov (make-overlay (match-beginning 0) (match-end 0))))
        (overlay-put ov 'display
                     (propertize (format "[%s]" (match-string 1))
                                 'face 'org-snitch-link-face))
        (overlay-put ov 'org-snitch-link t)
        (overlay-put ov 'cursor-sensor-functions
                     (list #'org-snitch--cursor-sensor))))))

(defun org-snitch--clear-overlays ()
  "Remove all `org-snitch-link' overlays from the current buffer."
  (remove-overlays (point-min) (point-max) 'org-snitch-link t))

(defun org-snitch--cursor-sensor (_window old-pos action)
  "Show real link when cursor inside, restoring overlay when exiting.
_WINDOW is unused.  OLD-POS is the previous cursor position.
ACTION is `entered`."
  (if (eq action 'entered)
      (dolist (ov (overlays-at (point)))
        (when (overlay-get ov 'org-snitch-link)
          (overlay-put ov 'display nil)))
    (dolist (ov (overlays-at old-pos))
      (when (overlay-get ov 'org-snitch-link)
        (save-excursion
          (goto-char (overlay-start ov))
          (when (looking-at org-snitch-link-overlay-regexp)
            (overlay-put ov 'display
                         (propertize (format "[%s]" (match-string 1))
                                     'face 'org-snitch-link-face))))))))

(defvar org-snitch-link-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-o") #'org-open-at-point-global)
    map)
  "Keymap for `org-snitch-link-mode'.")

;;;###autoload
(define-minor-mode org-snitch-link-mode
  "Renders org link as overlays in non-org buffers."
  :lighter " SnitchLink"
  (if org-snitch-link-mode
      (progn
        (cursor-sensor-mode 1)
        (org-snitch--make-overlays)
        (add-hook 'after-save-hook #'org-snitch--make-overlays nil t)
        (add-hook 'after-change-functions
                  (lambda (&rest _)
                    (org-snitch--clear-overlays)
                    (org-snitch--make-overlays)) nil t))
    (cursor-sensor-mode -1)
    (org-snitch--clear-overlays)
    (remove-hook 'after-save-hook #'org-snitch--make-overlays t)
    (remove-hook 'after-change-functions
                 (lambda (&rest _)
                   (org-snitch--clear-overlays)
                   (org-snitch--make-overlays)) t)))

;;;###autoload
(defun org-snitch-set-id-from-heading ()
  "Add an ID property and TASK_NUM to the capture heading.
This triggers after a project capture finalize, generating
deterministic IDs based on heading text, and assigning sequential numbers."
  (interactive)
  (when (and org-snitch--key
             (string-prefix-p org-snitch-capture-key org-snitch--key)
             (markerp org-capture-last-stored-marker)
             (marker-buffer org-capture-last-stored-marker))
    (with-current-buffer (marker-buffer org-capture-last-stored-marker)
      (save-excursion
        (goto-char org-capture-last-stored-marker)
        (org-back-to-heading t)
        (let* ((title (org-get-heading t t t t))
               (hash (md5 title))
               task-num)
          (org-set-property "ID" hash)
          (unless (org-entry-get nil "TASK_NUM")
            (setq task-num (org-snitch--next-task-num (current-buffer)))
            (org-set-property "TASK_NUM" (number-to-string task-num)))
          (save-buffer))))))

(defun org-snitch--next-task-num (buffer)
  "Return the next TASK_NUM for the project in BUFFER."
  (with-current-buffer buffer
    (let ((max-num 0))
      (org-map-entries
       (lambda ()
         (when-let ((num (org-entry-get nil "TASK_NUM")))
           (setq max-num (max max-num (string-to-number num)))))
       nil 'file)
      (1+ max-num))))

;;;###autoload
(defun org-snitch-store-region-before (&rest _)
  "Store the active region boundaries before capturing.
This runs as `advice-add' :before on `org-capture'."
  (unless org-snitch--source-buffer
    (cond
     ((use-region-p)
      (setq org-snitch--source-buffer (current-buffer)
            org-snitch--region-beg-marker (copy-marker (region-beginning))
            org-snitch--region-end-marker (copy-marker (region-end) t)))
     ((save-excursion
        (beginning-of-line)
        (re-search-forward (rx word-start (or "TODO" "FIXME" "XXX") word-end) (line-end-position) t))
      (setq org-snitch--source-buffer (current-buffer)
            org-snitch--region-beg-marker (copy-marker (match-beginning 0))
            org-snitch--region-end-marker (copy-marker (line-end-position) t))))))

;;;###autoload
(defun org-snitch-store-key ()
  "Store the capture key currently being used in `org-snitch--key'."
  (setq org-snitch--key (plist-get org-capture-current-plist :key)))

;;;###autoload
(defun org-snitch-cleanup ()
  "Clean up `org-snitch' internal state variables post-capture."
  (setq org-snitch--source-buffer nil
        org-snitch--region-beg-marker nil
        org-snitch--region-end-marker nil
        org-snitch--key nil))

;;;###autoload
(defun org-snitch-update-id-locations ()
  "Update `org-id-locations' for the target project file after capture."
  (when (and org-snitch--key
             (string-prefix-p org-snitch-capture-key org-snitch--key))
    (org-id-update-id-locations
     (list (org-snitch-find-project-file)))))

;;;###autoload
(defun org-snitch-find-project-file ()
  "Return the path for `org-snitch-target-file'."
  (expand-file-name org-snitch-target-file (org-snitch--get-project-root)))

(defun org-snitch--task-candidates ()
  "Return an alist of task candidates from the current project file.
Each element is (DISPLAY-STRING ID TASK-NUM HEADING PARENT)."
  (let ((project-file (org-snitch-find-project-file)))
    (delq nil
          (with-current-buffer (find-file-noselect project-file)
            (org-map-entries
             (lambda ()
                 (let ((id (org-entry-get nil "ID"))
                       (todo (org-get-todo-state))
                       (task-num (org-entry-get nil "TASK_NUM"))
                       (heading (org-get-heading t t t t))
                       (parent (save-excursion
                                 (when (org-up-heading-safe)
                                   (upcase (org-get-heading t t t t))))))
                   (when id
                     (list (format "%s #%s %s: %s"
                                   (or parent "TASK") (or task-num "?")
                                   (or todo "") heading)
                           id task-num heading parent))))
             nil 'file)))))

(defun org-snitch--format-link (id task-num heading parent)
  "Format a task link string from ID, TASK-NUM, HEADING, and PARENT.
When in a buffer with `comment-start', wraps the result in comment syntax."
  (let* ((clean-heading (string-join (cdr (split-string heading)) " "))
         (link (format "%s: (#%s) [[id:%s][%s]]"
                       (or parent "TASK") (or task-num "?") id clean-heading)))
    (if (and (bound-and-true-p comment-start)
             (not (derived-mode-p 'org-mode)))
        (format "%s %s %s" comment-start link (or comment-end ""))
      link)))

;;;###autoload
(defun org-snitch-insert-link ()
  "Insert a project task link.
When called interactively, presents project tasks via `completing-read'
and inserts the formatted link at point.  When called as a capture
hook with an active region, replaces the region with the link."
  (interactive)
  (let ((in-capture-hook (and org-snitch--key
                              (string-prefix-p org-snitch-capture-key org-snitch--key)
                              (not (called-interactively-p 'any)))))
    (cond
     ;; 1. Called as a hook AND we have an active region stored
     ((and in-capture-hook
           org-snitch--source-buffer
           org-snitch--region-beg-marker
           org-snitch--region-end-marker
           (markerp org-capture-last-stored-marker)
           (marker-buffer org-capture-last-stored-marker))
      (let (id task-num heading parent)
        (with-current-buffer (marker-buffer org-capture-last-stored-marker)
          (save-excursion
            (goto-char org-capture-last-stored-marker)
            (org-back-to-heading t)
            (setq id (org-entry-get nil "ID"))
            (setq task-num (org-entry-get nil "TASK_NUM"))
            (setq heading (org-get-heading t t t t))
            (setq parent (save-excursion
                           (when (org-up-heading-safe)
                             (upcase (org-get-heading t t t t)))))))
        (with-current-buffer org-snitch--source-buffer
          (save-excursion
            (goto-char org-snitch--region-beg-marker)
            (delete-region org-snitch--region-beg-marker
                           org-snitch--region-end-marker)
            (insert (org-snitch--format-link id task-num heading parent))))))

     ;; 2. Called as a hook but NO region was stored AND we have a valid source buffer
     ((and in-capture-hook org-snitch--source-buffer)
      (when (y-or-n-p "Insert task link at point? ")
        (let (id task-num heading parent)
          (with-current-buffer (marker-buffer org-capture-last-stored-marker)
            (save-excursion
              (goto-char org-capture-last-stored-marker)
              (org-back-to-heading t)
              (setq id (org-entry-get nil "ID"))
              (setq task-num (org-entry-get nil "TASK_NUM"))
              (setq heading (org-get-heading t t t t))
              (setq parent (save-excursion
                             (when (org-up-heading-safe)
                               (upcase (org-get-heading t t t t)))))))
          (with-current-buffer org-snitch--source-buffer
            (insert (org-snitch--format-link id task-num heading parent))))))

     ;; 3. Interactive/fallback: use completing-read only if NOT in capture hook
     ((not in-capture-hook)
      (let* ((candidates (org-snitch--task-candidates))
             (choice (completing-read "Task: " (mapcar #'car candidates) nil t))
             (entry (assoc choice candidates)))
        (insert (org-snitch--format-link
                 (nth 1 entry) (nth 2 entry)
                 (nth 3 entry) (nth 4 entry))))))))

;;;###autoload
(defun org-snitch-find-references ()
  "Find all references to a project task across the codebase.
Presents tasks via `completing-read', then searches the project
for occurrences of the selected task's ID using `xref'."
  (interactive)
  (let* ((candidates (org-snitch--task-candidates))
         (choice (completing-read "Find references for: "
                                  (mapcar #'car candidates) nil t))
         (entry (assoc choice candidates))
         (id (nth 1 entry))
         (files (let ((project-vc-merge-submodules
                       (not org-snitch-independent-submodules)))
                  (project-files (project-current t)))))
    (xref-show-xrefs
     (lambda () (xref-matches-in-files
                   (regexp-quote (format "id:%s" id)) files))
     nil)))

;;;###autoload
(defun org-snitch-magit-insert-task ()
  "Insert a project task reference in a git commit message.
Prompts for a Git action verb (e.g. Resolves, Refs) and then
for a project task, inserting the formatted reference at point.
Designed to be bound in `git-commit-mode-map'."
  (interactive)
  (let* ((verbs '("Resolves" "Fixes" "Closes" "Refs" "Related to"))
         (verb (completing-read "Action: " verbs nil nil))
         (candidates (org-snitch--task-candidates))
         (choice (completing-read "Task: " (mapcar #'car candidates) nil t))
         (entry (assoc choice candidates))
         (task-num (nth 2 entry))
         (heading (nth 3 entry))
         (clean-heading (string-join (cdr (split-string heading)) " ")))
    (insert (format "%s #%s: %s" verb task-num clean-heading))))

(defvar git-commit-mode-map)
(with-eval-after-load 'git-commit
  (define-key git-commit-mode-map (kbd "C-c C-t") #'org-snitch-magit-insert-task))

;;;###autoload
(define-minor-mode org-snitch-mode
  "Global minor mode to enable org-snitch project hooks for `org-capture'."
  :global t
  :lighter " snitch"
  (if org-snitch-mode
      (progn
        (advice-add 'org-capture :before #'org-snitch-store-region-before)
        (add-hook 'org-capture-mode-hook  #'org-snitch-store-key)
        (add-hook 'org-capture-after-finalize-hook #'org-snitch-cleanup t))
    (advice-remove 'org-capture #'org-snitch-store-region-before)
    (remove-hook 'org-capture-mode-hook #'org-snitch-store-key)
    (remove-hook 'org-capture-after-finalize-hook #'org-snitch-cleanup t)))

(provide 'org-snitch)
;;; org-snitch.el ends here
