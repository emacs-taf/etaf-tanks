;;; -*- lexical-binding: t; -*-
;;; etaf-tanks.el --- Iron Tide, a standalone GameKit tank battle

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf-gamekit "0.1.0") (etaf-ui "0.1.0"))
;;; Commentary:
;; Iron Tide is a real-time tank battle in a headless Godot world. Its fixed
;; physics clock advances movement, swept collisions, ballistics and enemy AI
;; independently of player input. ETAF presents a line-sliced vector arena,
;; both palettes, controls and the battle log without duplicating those rules.
;;
;; Variable: etaf-tanks-game
;; Inert game definition usable with etaf-gamekit-start. The bundled Godot
;; project is resolved from this application entry, not from GameKit. Each
;; instance owns an independent battlefield.
;;
;; Variable: etaf-tanks-appearance
;; Initial appearance for new instances: auto (default), light or dark. Auto
;; follows the opening frame's background mode. Each instance can switch
;; independently with the theme button or T without resetting the battle.
;;
;; Function: etaf-tanks-open ()
;;;###autoload (autoload 'etaf-tanks-open "etaf-tanks" nil t)
;; Start and display an independent sortie; return its GameKit instance.
;; Requires Godot installed by GameKit. The battle starts paused; P begins it.
;; No snapshot is loaded implicitly. Save/Load choose explicit local paths;
;; restore validates first, resumes paused and clears routes/in-flight shells.
;;
;; Function: etaf-tanks-close (&optional instance)
;;;###autoload (autoload 'etaf-tanks-close "etaf-tanks" nil t)
;; Close INSTANCE and its buffer. Omitted uses the current Iron Tide buffer.
;; No automatic save is performed.
;;
;;; Code:
(require 'etaf-gamekit)
(require 'etaf-ui)
(defgroup etaf-tanks nil "Iron Tide tank battle." :group 'games)
(defcustom etaf-tanks-appearance 'auto
  "Initial appearance of new Iron Tide instances."
  :type '(choice (const auto) (const light) (const dark)) :group 'etaf-tanks)
(defconst etaf-tanks--directory
  (file-name-directory (or load-file-name buffer-file-name)))
(let ((load-path (cons (expand-file-name "lisp" etaf-tanks--directory) load-path)))
  (require 'etaf-tanks-theme)
  (require 'etaf-tanks-model)
  (require 'etaf-tanks-views)
  (require 'etaf-tanks-app))
(provide 'etaf-tanks)
;;; etaf-tanks.el ends here
