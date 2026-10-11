;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-app.el --- Standalone game definition and lifetime

;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-gamekit)
(require 'etaf-tanks-views)

(defvar etaf-tanks--directory)
(defvar-local etaf-tanks--session nil)

(etaf-gamekit-define-game etaf-tanks-game
  :title "Iron Tide · 钢铁洪流" :backend 'godot
  :options (list :project (expand-file-name "native/godot" etaf-tanks--directory))
  :validate #'etaf-tanks--valid-p
  :view #'etaf-tanks--view)

(defun etaf-tanks--pause-on-leave (window)
  "Pause this buffer's battle when WINDOW no longer selects or shows it."
  (when (and etaf-tanks--session (window-live-p window)
             (or (not (eq (window-buffer window) (current-buffer)))
                 (not (eq window (frame-selected-window (window-frame window))))))
    (etaf-tanks--pause-for-input etaf-tanks--session)))

(defun etaf-tanks-open ()
  "Start and display an independent Iron Tide sortie."
  (interactive)
  (let* ((session (etaf-gamekit-start etaf-tanks-game))
         (buffer (etaf-gamekit-buffer session)))
    (with-current-buffer buffer
      (setq-local etaf-tanks--session session cursor-type nil mode-line-format nil truncate-lines t
                  buffer-display-table (copy-sequence (or standard-display-table (make-display-table))))
      (set-display-table-slot buffer-display-table 'truncation ?\s)
      (add-hook 'window-buffer-change-functions #'etaf-tanks--pause-on-leave nil t)
      (add-hook 'window-selection-change-functions #'etaf-tanks--pause-on-leave nil t))
    (switch-to-buffer buffer)
    (etaf-refit (etaf-runtime-for-buffer buffer) (selected-window))
    session))

(defun etaf-tanks-close (&optional instance)
  "Close INSTANCE, or the current Iron Tide instance, without implicit saving."
  (interactive)
  (let ((session (or instance etaf-tanks--session)))
    (unless session (user-error "This is not an Iron Tide buffer"))
    (etaf-gamekit-close session)
    (when (buffer-live-p (etaf-gamekit-buffer session))
      (kill-buffer (etaf-gamekit-buffer session)))))

(provide 'etaf-tanks-app)
;;; etaf-tanks-app.el ends here
