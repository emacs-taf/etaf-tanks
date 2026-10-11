;;; -*- lexical-binding: t; -*-
;;; performance-scenarios.el --- Iron Tide input-to-publication workloads
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-tanks)
(declare-function taf-benchmark-register "performance-driver" (id &rest properties))

(defun etaf-tanks-benchmark--fixture (mode operation)
  "Create one independent battlefield for MODE and measured OPERATION."
  (let* ((etaf-tanks-appearance 'light) (session (etaf-tanks-open))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
         original-size expected fitted)
    (list
     :buffer (etaf-gamekit-buffer session)
     :ready (lambda ()
              (unless fitted
                (if (eq mode 'batch) (etaf-runtime-refit runtime 1100 44)
                  (etaf-refit runtime (selected-window)))
                (setq fitted t))
              (setq original-size (etaf-host-ref-size runtime 'tanks-board))
              (and original-size (eq (etaf-gamekit-status session) 'ready)))
     :invoke
     (lambda (_index)
       (pcase operation
         ('aim
          (setq expected (if (equal (plist-get (etaf-gamekit-view session :player) :facing) "n") "e" "n"))
          (etaf-dispatch-event runtime (intern (concat "tanks-aim-" expected)) 'press))
         ('theme
          (setq expected (if (equal (plist-get (etaf-runtime-host-props-for runtime 'tanks-theme) :aria-label) "暗色")
                             "浅色" "暗色"))
          (etaf-dispatch-event runtime 'tanks-theme 'press))
         ('pause
          (setq expected (if (eq t (plist-get (etaf-gamekit-view session :player) :paused)) :false t))
          (etaf-dispatch-event runtime 'tanks-pause 'press))
         ('resize
          (setq expected (if (= (car (etaf-runtime-viewport runtime)) 650) 1100 650))
          (etaf-runtime-refit runtime expected 34))))
     :settled
     (lambda ()
       (and (eq (etaf-gamekit-status session) 'ready)
            (pcase operation
              ('aim (equal expected (plist-get (etaf-gamekit-view session :player) :facing)))
              ('theme (equal expected (plist-get (etaf-runtime-host-props-for runtime 'tanks-theme) :aria-label)))
              ('pause (eq expected (plist-get (etaf-gamekit-view session :player) :paused)))
              ('resize (= expected (car (etaf-runtime-viewport runtime)))))))
     :verify (lambda ()
               (and (not (etaf-gamekit-last-error session))
                    (not (eq t (plist-get (etaf-gamekit-view session :player) :lost)))
                    (equal original-size (etaf-host-ref-size runtime 'tanks-board))))
     :outcome (lambda () (list :operation (symbol-name operation)
                              :arena (let ((size (etaf-host-ref-size runtime 'tanks-board)))
                                       (vector (car size) (cdr size)))))
     :cleanup (lambda () (etaf-tanks-close session)))))

(dolist (case '((aim 50 "Aim through Godot to a changed native tank silhouette")
                (theme 50 "Repaint the complete battlefield and controls")
                (pause 50 "Start or pause an autonomous battle through its rendered control")
                (resize 50 "Refit the interface without stretching the arena")))
  (let ((operation (car case)))
    (taf-benchmark-register (format "etaf-tanks.%s" operation)
      :version 1 :modes '(batch gui) :isolation 'series :impact 'subtree
      :budget-ms (cadr case) :description (caddr case)
      :setup (lambda (mode) (etaf-tanks-benchmark--fixture mode operation)))))
(defun etaf-tanks-benchmark--keys (operation)
  "Measure real command-loop input during an autonomous live battle.
Driving uses fresh worlds for a clear departure lane. Aiming and loaded
shots use a continuous battle; a terminal battle is renewed through the
public restart/start actions in readiness, never inside the measured input."
  (unless (and (display-graphic-p) (image-type-available-p 'svg))
    (error "Native-input workloads require a graphical SVG display"))
  (let* ((session (etaf-tanks-open))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
         (battle 1) expected before-image before-position key fitted)
    (cl-labels
        ((state () (etaf-gamekit-view session :player))
         (canvas () (plist-get (etaf-runtime-host-props-for runtime 'tanks-canvas) :src))
         (position () (let ((tank (car (plist-get (etaf-gamekit-view session :world) :entities))))
                        (cons (plist-get tank :px) (plist-get tank :py)))))
      (list
       :buffer (etaf-gamekit-buffer session)
       :environment (lambda () (list :input "Emacs command loop" :simulation "live 60 Hz Godot"
                                    :completion "committed canvas change plus driver redisplay"
                                    :renewal (if (eq operation 'drive) "fresh departure lane" "restart after terminal battle")))
       :ready
       (lambda ()
         (when (memq (etaf-gamekit-status session) '(failed closed))
           (error "Battle fixture failed: %s" (etaf-gamekit-last-error session)))
         (unless fitted (etaf-refit runtime (selected-window)) (setq fitted t))
         (when (and (eq (etaf-gamekit-status session) 'ready) (etaf-host-ref-size runtime 'tanks-board))
           (cond
            ((or (eq t (plist-get (state) :won)) (eq t (plist-get (state) :lost)))
             (cl-incf battle) (etaf-gamekit-action session "restart") nil)
            ((eq t (plist-get (state) :paused)) (etaf-gamekit-action session "pause") nil)
            ((eq operation 'fire) (eq t (plist-get (state) :can_fire)))
            (t t))))
       :prepare (lambda () (etaf-focus runtime 'tanks-board))
       :invoke
       (lambda (_index)
         (setq before-image (canvas) before-position (position))
         (pcase operation
           ('drive (setq key "d" expected (car before-position)))
           ('aim (setq expected (if (equal (plist-get (state) :facing) "n") "e" "n")
                       key (if (equal expected "n") "W" "D")))
           ('fire (setq key "SPC" expected (1+ (plist-get (state) :shots)))))
         (execute-kbd-macro (kbd key)))
       :settled
       (lambda ()
         (and (eq (etaf-gamekit-status session) 'ready)
              (not (equal before-image (canvas)))
              (pcase operation
                ('drive (> (car (position)) expected))
                ('aim (equal expected (plist-get (state) :facing)))
                ('fire (= expected (plist-get (state) :shots))))))
       :verify (lambda () (and (not (etaf-gamekit-last-error session))
                               (not (eq t (plist-get (state) :paused)))
                               (etaf-host-ref-size runtime 'tanks-board) t))
       :outcome (lambda () (list :key key :battle battle :position (vector (car (position)) (cdr (position)))
                                :shots (plist-get (state) :shots) :seconds (plist-get (state) :seconds)
                                :health (plist-get (state) :health)))
       :cleanup (lambda () (etaf-tanks-close session))))))

(dolist (case '((drive fresh "Drive key to the first visibly moved tank in a live arena")
                (aim series "Repeated aiming keys while enemies and shells keep moving")
                (fire series "Repeated loaded shots through Space and visible projectiles")))
  (let ((operation (car case)))
    (taf-benchmark-register (format "etaf-tanks.keys.%s" operation)
      :version 1 :modes '(gui) :isolation (cadr case) :impact 'subtree
      :budget-ms 50 :description (caddr case)
      :setup (lambda (_mode) (etaf-tanks-benchmark--keys operation)))))

(provide 'etaf-tanks-performance-scenarios)
;;; performance-scenarios.el ends here
