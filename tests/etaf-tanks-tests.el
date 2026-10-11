;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-tests.el --- Real physics and application input contracts
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'ert)
(require 'etaf-tanks)

(defun etaf-tanks-test--wait (session &optional predicate seconds)
  "Await ready SESSION and PREDICATE for at most SECONDS."
  (let ((end (+ (float-time) (or seconds 8))))
    (while (and (< (float-time) end)
                (not (memq (etaf-gamekit-status session) '(failed closed)))
                (or (not (eq (etaf-gamekit-status session) 'ready))
                    (and predicate (not (funcall predicate)))))
      (accept-process-output nil 0.01)))
  (let ((status (etaf-gamekit-status session))
        (settled (or (null predicate) (funcall predicate))))
    (should (eq status 'ready)) (should settled)))

(defun etaf-tanks-test--state (session)
  "Read SESSION's authoritative public battle summary."
  (plist-get (etaf-gamekit-observation session) :player))

(defun etaf-tanks-test--tank (session)
  "Read the player entity in SESSION's public world."
  (cl-find "player" (plist-get (plist-get (etaf-gamekit-observation session) :world) :entities)
           :key (lambda (entity) (plist-get entity :id)) :test #'equal))

(defun etaf-tanks-test--start ()
  "Start and paint a paused match, cleaning up if startup fails."
  (let* ((session (etaf-gamekit-start etaf-tanks-game))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))) good)
    (unwind-protect
        (progn
          (etaf-runtime-refit runtime 1100 44)
          (etaf-tanks-test--wait session (lambda () (etaf-host-ref-size runtime 'tanks-board)))
          (let ((error (etaf-gamekit-last-error session))) (should-not error))
          (setq good t)
          session)
      (unless good (etaf-tanks-close session)))))

(defun etaf-tanks-test--act (session operation &optional args rejection)
  "Send OPERATION with ARGS and verify acknowledgement or expected REJECTION."
  (etaf-gamekit-action session operation args)
  (etaf-tanks-test--wait session)
  (let ((failure (etaf-gamekit-last-error session)))
    (if rejection (should failure) (should-not failure)))
  (etaf-gamekit-observation session))

(ert-deftest etaf-tanks-world-runs-without-input-and-pauses-atomically ()
  "Enemies move under Godot's physics clock, not once per user command."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (let ((before (plist-get (etaf-gamekit-observation session) :world)))
          (etaf-tanks-test--act session "pause")
          ;; No commands are sent while the enemies advance.
          (etaf-tanks-test--wait session
            (lambda () (not (equal before (plist-get (etaf-gamekit-observation session) :world)))))
          (etaf-tanks-test--act session "pause")
          (let ((frozen (etaf-gamekit-observation session)) (until (+ (float-time) 0.3)))
            (while (< (float-time) until) (accept-process-output nil 0.01))
            (let ((after (etaf-gamekit-observation session))) (should (equal frozen after)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-physics-stops-overlapping-armour ()
  "A navigation order cannot drive the player through another tank."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (progn
          (etaf-tanks-test--act session "pause")
          (etaf-tanks-test--act session "navigate" '(:x 8 :y 10))
          (etaf-tanks-test--wait session
            (lambda () (and (> (plist-get (etaf-tanks-test--tank session) :px) 4)
                            (eq :false (plist-get (etaf-tanks-test--state session) :moving)))))
          (etaf-tanks-test--act session "pause")
          (let* ((world (plist-get (etaf-gamekit-observation session) :world))
                 (tank (etaf-tanks-test--tank session))
                 (enemy (cl-find "enemy-1" (plist-get world :entities)
                                 :key (lambda (entity) (plist-get entity :id)) :test #'equal))
                 (separation (- (plist-get enemy :px) (plist-get tank :px))))
            (should (>= separation 0.59))
            (should (= 7 (plist-get tank :x)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-invalid-orders-preserve-paused-world ()
  "Rejected coordinates, directions and malformed snapshots cannot change state."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (let ((before (etaf-gamekit-observation session)))
          (dolist (order '(("aim" :direction "diagonal") ("navigate" :x 0 :y 0)
                           ("move" :x 1.5 :y 0) ("fire") ("load" :path 12)))
            (let ((after (etaf-tanks-test--act session (car order) (cdr order) t)))
              (should (equal before after)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-shells-stop-at-cover ()
  "A fired shell collides with the arena wall without damaging a raider."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (progn
          (etaf-tanks-test--act session "aim" '(:direction "w"))
          (etaf-tanks-test--act session "pause")
          (etaf-tanks-test--act session "fire")
          (etaf-tanks-test--wait session
            (lambda () (null (plist-get (plist-get (etaf-gamekit-observation session) :world) :shells))))
          (etaf-tanks-test--act session "pause")
          (let ((state (etaf-tanks-test--state session)))
            (should (= 1 (plist-get state :shots)))
            (should (= 0 (plist-get state :kills)))
            (should (= 3 (plist-get state :enemies)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-native-controls-can-win-and-restart ()
  "Rendered controls aim and fire against autonomous enemies through victory."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
              (deadline (+ (float-time) 18)))
          (etaf-dispatch-event runtime 'tanks-pause 'press)
          (while (and (< (float-time) deadline)
                      (not (eq t (plist-get (etaf-tanks-test--state session) :won)))
                      (not (eq t (plist-get (etaf-tanks-test--state session) :lost))))
            (when (eq (etaf-gamekit-status session) 'ready)
              (let* ((world (plist-get (etaf-gamekit-observation session) :world))
                     (me (etaf-tanks-test--tank session)) direction)
                ;; A caller uses only positions published by the native world.
                (dolist (enemy (cdr (plist-get world :entities)))
                  (let ((dx (- (plist-get enemy :px) (plist-get me :px)))
                        (dy (- (plist-get enemy :py) (plist-get me :py))))
                    (cond ((< (abs dx) 0.3) (setq direction (if (< dy 0) "n" "s")))
                          ((< (abs dy) 0.3) (setq direction (if (< dx 0) "w" "e"))))))
                (when direction
                  (if (not (equal direction (plist-get (etaf-tanks-test--state session) :facing)))
                      (etaf-dispatch-event runtime (intern (concat "tanks-aim-" direction)) 'press)
                    (unless (plist-get (etaf-runtime-host-props-for runtime 'tanks-fire) :disabled)
                      (etaf-dispatch-event runtime 'tanks-fire 'press))))))
            (accept-process-output nil 0.015))
          (etaf-tanks-test--wait session)
          (let ((state (etaf-tanks-test--state session)))
            (should (eq t (plist-get state :won)))
            (should (= 3 (plist-get state :kills)))
            (should (> (plist-get state :seconds) 0)))
          (etaf-dispatch-event runtime 'tanks-new 'press)
          (etaf-tanks-test--wait session (lambda () (= 0 (plist-get (etaf-tanks-test--state session) :kills))))
          (let ((state (etaf-tanks-test--state session)))
            (should (eq t (plist-get state :paused)))
            (should (= 100 (plist-get state :health)))
            (should (= 3 (plist-get state :enemies)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-enemies-can-end-an-unattended-battle ()
  "Enemies can destroy an idle player without any later player input."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (progn
          (etaf-tanks-test--act session "pause")
          (etaf-tanks-test--wait session (lambda () (eq t (plist-get (etaf-tanks-test--state session) :lost))) 16)
          (let ((state (etaf-tanks-test--state session))) (should (= 0 (plist-get state :health))))
          (let ((ended (etaf-gamekit-observation session)))
            (let ((after (etaf-tanks-test--act session "fire" nil t))) (should (equal ended after)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-snapshots-restore-paused-with-atomic-rejection ()
  "A snapshot restores positions and resources; malformed input keeps the match."
  (let ((session (etaf-tanks-test--start)) (file (make-temp-file "iron-tide-")))
    (unwind-protect
        (progn
          (etaf-tanks-test--act session "pause")
          (etaf-tanks-test--act session "move" '(:x 1 :y 0))
          (etaf-tanks-test--wait session (lambda () (>= (plist-get (etaf-tanks-test--tank session) :px) 4.5)))
          (etaf-tanks-test--act session "pause")
          (let ((before (etaf-gamekit-observation session)))
            (etaf-tanks-test--act session "save" (list :path file))
            (etaf-tanks-test--act session "restart")
            (etaf-tanks-test--act session "load" (list :path file))
            (let ((after (etaf-gamekit-observation session)))
              (should (equal (plist-get (plist-get before :world) :entities)
                             (plist-get (plist-get after :world) :entities)))
              (should (eq t (plist-get (plist-get after :player) :paused)))
              (dolist (bad '("{broken" "{}" "[]"))
                (with-temp-file file (insert bad))
                (let ((unchanged (etaf-tanks-test--act session "load" (list :path file) t)))
                  (should (equal after unchanged)))))))
      (etaf-tanks-close session) (delete-file file))))

(ert-deftest etaf-tanks-themes-and-resize-preserve-paused-battle ()
  "Both palettes and viewport changes preserve the arena, state and focus."
  (let ((session (etaf-tanks-test--start)))
    (unwind-protect
        (let* ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
               (before (etaf-gamekit-observation session)) (size (etaf-host-ref-size runtime 'tanks-board)))
          (etaf-focus runtime 'tanks-board)
          (dotimes (index 2)
            (etaf-dispatch-event runtime 'tanks-theme 'press)
            (etaf-runtime-refit runtime (if (zerop index) 600 1100) 34)
            (let ((after (etaf-gamekit-observation session)) (now (etaf-host-ref-size runtime 'tanks-board))
                  (focus (etaf-focused-host-ref runtime)))
              (should (equal before after)) (should (equal size now)) (should (eq focus 'tanks-board)))))
      (etaf-tanks-close session))))

(ert-deftest etaf-tanks-battles-are-independent ()
  "One live battle cannot advance a second paused battlefield."
  (let ((first (etaf-tanks-test--start)) (second (etaf-tanks-test--start)))
    (unwind-protect
        (let ((before (etaf-gamekit-observation second)))
          (etaf-tanks-test--act first "pause")
          (etaf-tanks-test--wait first (lambda () (> (plist-get (etaf-tanks-test--state first) :seconds) 0)))
          (let ((after (etaf-gamekit-observation second))) (should (equal before after))))
      (etaf-tanks-close first) (etaf-tanks-close second))))

(provide 'etaf-tanks-tests)
;;; etaf-tanks-tests.el ends here
