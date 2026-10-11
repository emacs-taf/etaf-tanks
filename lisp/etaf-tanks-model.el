;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-model.el --- Public observation validation and battle commands
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'cl-lib)
(require 'etaf-gamekit)

(defun etaf-tanks--valid-p (observation)
  "Validate OBSERVATION before GameKit publishes it to this application."
  (let* ((world (plist-get observation :world)) (rows (plist-get world :terrain))
         (player (plist-get observation :player)))
    (and (equal (plist-get observation :schema) "tanks/1")
         (equal (plist-get world :width) 21) (equal (plist-get world :height) 13)
         (proper-list-p rows) (= (length rows) 13)
         (cl-every (lambda (row) (and (stringp row) (= (length row) 21)
                                     (not (string-match-p "[^.#]" row)))) rows)
         (integerp (plist-get player :health)) (<= 0 (plist-get player :health) 100)
         (integerp (plist-get player :kills)) (<= 0 (plist-get player :kills) 3)
         (cl-every (lambda (key) (memq (plist-get player key) '(t :false)))
                   '(:paused :won :lost :can_fire :moving))
         (proper-list-p (plist-get world :entities))
         (consp (plist-get world :entities))
         (cl-every (lambda (entity)
                     (and (member (plist-get entity :kind) '("player" "enemy"))
                          (member (plist-get entity :facing) '("n" "e" "s" "w"))
                          (numberp (plist-get entity :px)) (numberp (plist-get entity :py))
                          (<= 0 (plist-get entity :px) 21) (<= 0 (plist-get entity :py) 13)))
                   (plist-get world :entities))
         t)))

(defun etaf-tanks--ended-p (player)
  "Whether the public PLAYER record reports a terminal battle."
  (or (eq t (plist-get player :won)) (eq t (plist-get player :lost))))

(defun etaf-tanks--facing-glyph (facing)
  "Return the text fallback for FACING."
  (pcase facing ("n" "▲") ("e" "▶") ("s" "▼") ("w" "◀") (_ "?")))

(defun etaf-tanks--cell (world row column)
  "Describe one native cell in WORLD for text-only displays."
  (let ((entity (cl-find-if (lambda (item) (and (= row (plist-get item :y)) (= column (plist-get item :x))))
                            (plist-get world :entities)))
        (shell (cl-find-if (lambda (item) (and (= row (plist-get item :y)) (= column (plist-get item :x))))
                           (plist-get world :shells))))
    (cond (entity (list (if (equal (plist-get entity :kind) "player") :player :enemy)
                        (etaf-tanks--facing-glyph (plist-get entity :facing))))
          (shell (list :shell "•"))
          ((eq (aref (nth row (plist-get world :terrain)) column) ?#) (list :wall "▪"))
          (t (list :floor "·")))))

(defun etaf-tanks--send (session operation &optional arguments)
  "Send one advertised OPERATION and ARGUMENTS to a usable SESSION."
  (when (memq (etaf-gamekit-status session) '(ready busy))
    (etaf-gamekit-action session operation arguments)))

(defun etaf-tanks--move (session x y)
  "Queue one cardinal movement request X/Y. The native world owns motion."
  (let ((state (plist-get (etaf-gamekit-observation session) :player)))
    (when (and state (not (eq t (plist-get state :paused))) (not (etaf-tanks--ended-p state)))
      (etaf-tanks--send session "move" (list :x x :y y)))))

(defun etaf-tanks--fire (session)
  "Fire when the latest acknowledged observation reports a loaded cannon."
  (when (and (eq (etaf-gamekit-status session) 'ready)
             (eq t (plist-get (plist-get (etaf-gamekit-observation session) :player) :can_fire)))
    (etaf-tanks--send session "fire")))

(defun etaf-tanks--toggle-pause (session)
  "Toggle a live battle, matching the enabled state of its visible control."
  (let ((state (plist-get (etaf-gamekit-observation session) :player)))
    (when (and state (not (etaf-tanks--ended-p state)))
      (etaf-tanks--send session "pause"))))

(defun etaf-tanks--pause-for-input (session)
  "Pause a live battle before opening a modal or native input prompt."
  (let ((state (plist-get (etaf-gamekit-observation session) :player)))
    (when (and state (not (etaf-tanks--ended-p state)) (not (eq t (plist-get state :paused))))
      (etaf-tanks--send session "pause"))))

(defun etaf-tanks--snapshot (session operation)
  "Choose an explicit local snapshot path for OPERATION after pausing."
  (etaf-tanks--pause-for-input session)
  (when-let* ((file (etaf-call-with-input
                    (lambda () (read-file-name (if (equal operation "save") "保存战斗：" "读取战斗：")
                                               nil nil (equal operation "load") "iron-tide.json")))))
    (etaf-tanks--send session operation (list :path (expand-file-name file)))))

(provide 'etaf-tanks-model)
;;; etaf-tanks-model.el ends here
