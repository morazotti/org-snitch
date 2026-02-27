;;; org-snitch.el --- Project-specific org-capture and link faces -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Nícolas Morazotti

;; Author: Nícolas Morazotti
;; Maintainer: Nícolas Morazotti
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: org, project, outlines
;; URL: https://github.com/morazotti/org-snitch

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
                      :after-finalize org-snitch-set-id-from-heading)))
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
  "Add an ID property based on a hash algorithm."
  (interactive)
  (when (org-at-heading-p)
    (let* ((title (org-get-heading t t t t))
           (hash (md5 title)))
      (org-set-property "ID" hash))))

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
  (when (and (use-region-p) (null org-snitch--source-buffer))
    (setq org-snitch--source-buffer (current-buffer)
          org-snitch--region-beg-marker (copy-marker (region-beginning))
          org-snitch--region-end-marker (copy-marker (region-end) t))))

;;;###autoload
(defun org-snitch-store-key ()
  "Store the capture key currently being used in `org-snitch--key'."
  (setq org-snitch--key (plist-get org-capture-current-plist :key)))

;;;###autoload
(defun org-snitch-insert-link ()
  "Replace captured source region with a generated org-id link.
This triggers after finalizing the capture buffer if the capture
originates from a valid region and template key."
  (when (and org-snitch--source-buffer
             org-snitch--region-beg-marker
             org-snitch--region-end-marker
             (markerp org-capture-last-stored-marker)
             (marker-buffer org-capture-last-stored-marker)
             (string-prefix-p org-snitch-capture-key (or org-snitch--key "")))
    (let (id task-num region-text)
      (with-current-buffer (marker-buffer org-capture-last-stored-marker)
        (goto-char org-capture-last-stored-marker)
        (org-back-to-heading t)
        ;; ID
        (unless (org-entry-get nil "ID")
          (if (fboundp 'my/org-id-from-heading)
              (my/org-id-from-heading)
            (org-id-get-create)))
        (setq id (org-entry-get nil "ID"))
        ;; TASK_NUM
        (setq task-num (org-snitch--next-task-num (current-buffer)))
        (org-set-property "TASK_NUM" (number-to-string task-num))
        (save-buffer))
      (with-current-buffer org-snitch--source-buffer
        (setq region-text
              (buffer-substring-no-properties
               org-snitch--region-beg-marker
               org-snitch--region-end-marker))
        (save-excursion
          (goto-char org-snitch--region-beg-marker)
          (delete-region org-snitch--region-beg-marker
                         org-snitch--region-end-marker)
          (insert (format "(#%d) [[id:%s][%s]]"
                          task-num id region-text)))))))

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

;;;###autoload
(define-minor-mode org-snitch-mode
  "Global minor mode to enable org-snitch project hooks for `org-capture'."
  :global t
  :lighter " snitch"
  (if org-snitch-mode
      (progn
        (advice-add 'org-capture :before #'org-snitch-store-region-before)
        (add-hook 'org-capture-mode-hook  #'org-snitch-store-key)
        (add-hook 'org-capture-after-finalize-hook #'org-snitch-insert-link t)
        (add-hook 'org-capture-after-finalize-hook #'org-snitch-update-id-locations t)
        (add-hook 'org-capture-after-finalize-hook #'org-snitch-cleanup t))
    (advice-remove 'org-capture #'org-snitch-store-region-before)
    (remove-hook 'org-capture-mode-hook #'org-snitch-store-key)
    (remove-hook 'org-capture-after-finalize-hook #'org-snitch-insert-link t)
    (remove-hook 'org-capture-after-finalize-hook #'org-snitch-update-id-locations t)
    (remove-hook 'org-capture-after-finalize-hook #'org-snitch-cleanup t)))

(provide 'org-snitch)
;;; org-snitch.el ends here
