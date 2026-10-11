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
(defun etaf-tanks-benchmark--painted-images (runtime buffer)
  "Read the actual published image displays inside the battlefield.
This observes buffer output without depending on how the arena partitions it."
  (when-let* ((bounds (etaf-host-ref-bounds runtime 'tanks-board)))
    (with-current-buffer buffer
      (let ((position (car bounds)) (end (cdr bounds)) images)
        (while (< position end)
          (let* ((display (get-text-property position 'display))
                 (image (cond ((eq (car-safe display) 'image) display)
                              ((listp display)
                               (cl-find-if (lambda (part) (eq (car-safe part) 'image)) display)))))
            (when image (push image images)))
          (setq position (next-single-property-change position 'display nil end)))
        (nreverse images)))))

(defun etaf-tanks-benchmark--keys (operation)
  "Measure real command-loop input during an autonomous live battle.
Driving uses fresh worlds for a clear departure lane. Loaded shots fight
complete battles, preparing aim at aligned enemies outside the measured input.
Combined driving/firing renews its corridor after four live seconds. Terminal
battles restart through public actions in readiness."
  (unless (and (display-graphic-p) (image-type-available-p 'svg))
    (error "Native-input workloads require a graphical SVG display"))
  (let* ((session (etaf-tanks-open))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
         (battle 1) (victories 0) (defeats 0) expected expected-shots before-image before-position key fitted
         paint-observer paint-installed painted-at painted-position painted-images paint-gaps)
    (cl-labels
        ((state () (etaf-gamekit-view session :player))
         (canvas () (etaf-tanks-benchmark--painted-images runtime (etaf-gamekit-buffer session)))
         (position () (let ((tank (cl-find "player" (plist-get (etaf-gamekit-view session :world) :entities)
                                          :key (lambda (entity) (plist-get entity :id)) :test #'equal)))
                        (cons (plist-get tank :px) (plist-get tank :py))))
         (target-direction ()
           (let ((point (position)) direction distance)
             (dolist (enemy (plist-get (etaf-gamekit-view session :world) :entities))
               (when (equal (plist-get enemy :kind) "enemy")
                 (let* ((dx (- (plist-get enemy :px) (car point)))
                        (dy (- (plist-get enemy :py) (cdr point)))
                        (candidate (cond ((< (abs dx) 0.3) (if (< dy 0) "n" "s"))
                                         ((< (abs dy) 0.3) (if (< dx 0) "w" "e"))))
                        (range (+ (abs dx) (abs dy))))
                   (when (and candidate (or (null distance) (< range distance)))
                     (setq direction candidate distance range)))))
             direction))
         (redrawing (_window)
           (let ((moving (eq t (plist-get (state) :moving)))
                 (paused (eq t (plist-get (state) :paused))))
             (when (and (not paused) (or moving painted-at))
               (let ((point (position)) (images (canvas)) (now (float-time)))
                 (unless (or (equal point painted-position) (equal images painted-images))
                   (when painted-at (push (* 1000 (- now painted-at)) paint-gaps))
                   (setq painted-at now painted-position point painted-images images))))
             ;; Include the final moved frame before ending the segment: a
             ;; stall that covers the last part of a move must not disappear.
             (when (or paused (not moving))
               (setq painted-at nil painted-position nil painted-images nil)))))
      (setq paint-observer #'redrawing)
      (list
       :buffer (etaf-gamekit-buffer session)
       :environment (lambda () (list :input "Emacs command loop" :simulation "live 60 Hz Godot"
                                    :completion "committed canvas change plus driver redisplay"
                                    :renewal (pcase operation ('drive "fresh departure lane")
                                               ('drive-fire "four-second continuous live corridor")
                                               (_ "complete battles; restart after terminal state"))
                                    :fire-preparation "aim at aligned raiders; wait for native reload"
                                    :paint-observer (if (eq operation 'drive-fire)
                                                        "before redisplay during player motion; includes harness overhead" "none")))
       :ready
       (lambda ()
         (when (memq (etaf-gamekit-status session) '(failed closed))
           (error "Battle fixture failed: %s" (etaf-gamekit-last-error session)))
         (unless fitted (etaf-refit runtime (selected-window)) (setq fitted t))
         (when (and (eq (etaf-gamekit-status session) 'ready)
                    (etaf-host-ref-size runtime 'tanks-board)
                    (equal (state) (plist-get (etaf-gamekit-observation session) :player)))
           ;; The final position can be drawn one tick before :moving clears.
           ;; If clearing it needs no repaint, end the already-drawn segment
           ;; here; otherwise keep it until its final frame is actually offered.
           (when (and (eq operation 'drive-fire) painted-at
                      (not (eq t (plist-get (state) :moving)))
                      (equal (position) painted-position))
             (setq painted-at nil painted-position nil painted-images nil))
           (cond
            ((or (eq t (plist-get (state) :won)) (eq t (plist-get (state) :lost))
                 (and (eq operation 'drive-fire) (>= (plist-get (state) :seconds) 4)))
             (when (eq t (plist-get (state) :won)) (cl-incf victories))
             (when (eq t (plist-get (state) :lost)) (cl-incf defeats))
             (cl-incf battle) (etaf-gamekit-action session "restart") nil)
            ((eq t (plist-get (state) :paused)) (etaf-gamekit-action session "pause") nil)
            ((eq operation 'drive-fire)
             (and (eq t (plist-get (state) :can_fire)) (not (eq t (plist-get (state) :moving)))))
            ((eq operation 'fire)
             (when (and (eq t (plist-get (state) :can_fire))
                        ;; Let a possible winning projectile resolve before
                        ;; admitting another shot.  Nothing freezes the world.
                        (not (and (= 1 (plist-get (state) :enemies))
                                  (cl-some (lambda (shell) (equal (plist-get shell :owner) "player"))
                                           (plist-get (plist-get (etaf-gamekit-observation session) :world) :shells)))))
               (let ((direction (target-direction)))
                 (if (and direction (not (equal direction (plist-get (state) :facing))))
                     (progn (etaf-gamekit-action session "aim" (list :direction direction)) nil)
                   t))))
            (t t))))
       :prepare (lambda ()
                  (etaf-focus runtime 'tanks-board)
                  (when (and (eq operation 'drive-fire) (not paint-installed))
                    (with-current-buffer (etaf-gamekit-buffer session)
                      (add-hook 'pre-redisplay-functions paint-observer nil t))
                    (setq paint-installed t)))
       :invoke
       (lambda (_index)
         (setq before-image (canvas) before-position (position))
         (pcase operation
           ('drive (setq key "d" expected (car before-position)))
           ('drive-fire (setq expected (car before-position)
                              expected-shots (1+ (plist-get (state) :shots))
                              key (if (> expected 3.75) "a SPC" "d SPC")))
           ('aim (setq expected (if (equal (plist-get (state) :facing) "n") "e" "n")
                       key (if (equal expected "n") "W" "D")))
           ('fire (setq key "SPC" expected (1+ (plist-get (state) :shots)))))
         (execute-kbd-macro (kbd key)))
       :settled
       (lambda ()
         (when-let* ((failure (etaf-gamekit-last-error session)))
           (error "Native input rejected: %s" failure))
         (and (eq (etaf-gamekit-status session) 'ready)
              (not (equal before-image (canvas)))
              (pcase operation
                ('drive (> (car (position)) expected))
                ('drive-fire (and (= expected-shots (plist-get (state) :shots))
                                  (if (string-prefix-p "d" key) (> (car (position)) expected)
                                    (< (car (position)) expected))))
                ('aim (equal expected (plist-get (state) :facing)))
                ('fire (= expected (plist-get (state) :shots))))))
       :verify (lambda ()
                 (if (and (eq operation 'drive-fire) (>= (plist-get (state) :shots) 2)
                          (null paint-gaps))
                     "No continuous redraw evidence"
                   (and (not (etaf-gamekit-last-error session))
                        (or (not (eq t (plist-get (state) :paused)))
                            (eq t (plist-get (state) :won)))
                        (etaf-host-ref-size runtime 'tanks-board) t)))
       :outcome (lambda () (list :key key :battle battle :victories victories :defeats defeats
                                :position (vector (car (position)) (cdr (position)))
                                :shots (plist-get (state) :shots) :seconds (plist-get (state) :seconds)
                                :health (plist-get (state) :health) :won (plist-get (state) :won)
                                :moving-redraw-gaps-ms (vconcat (reverse paint-gaps))))
       :cleanup (lambda ()
                  (when (buffer-live-p (etaf-gamekit-buffer session))
                    (with-current-buffer (etaf-gamekit-buffer session)
                      (remove-hook 'pre-redisplay-functions paint-observer t)))
                  (etaf-tanks-close session))))))

(dolist (case '((drive fresh "Drive key to the first visibly moved tank in a live arena")
                (aim series "Repeated aiming keys while enemies and shells keep moving")
                (fire series "Repeated loaded shots through Space and visible projectiles")
                (drive-fire series "Continuous driving, alternating turns and simultaneous fire")))
  (let ((operation (car case)))
    (taf-benchmark-register (format "etaf-tanks.keys.%s" operation)
      :version 4 :modes '(gui) :isolation (cadr case) :impact 'subtree
      :budget-ms 50 :description (caddr case)
      :setup (lambda (_mode) (etaf-tanks-benchmark--keys operation)))))

(provide 'etaf-tanks-performance-scenarios)
;;; performance-scenarios.el ends here
