;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-gui-scenarios.el --- Real battlefield appearance and native input
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-tanks)
(require 'emacs-gui-verifier)

(defun etaf-tanks-gui--size (width rows)
  "Resize the dedicated frame toward WIDTH pixels and ROWS content lines."
  (let ((chrome (- (frame-pixel-height) (window-body-height nil t))))
    (set-frame-parameter nil 'fullscreen nil)
    (set-frame-size nil width (+ chrome (* rows (frame-char-height))) t)))

(defun etaf-tanks-gui-run (directory)
  "Exercise native input and both palettes in fresh evidence DIRECTORY.
Run in an existing dedicated graphical frame. The owned battle, temporary
snapshot and frame geometry are cleaned up after success or failure."
  (unless (display-graphic-p) (error "A graphical frame is required"))
  (let ((size (cons (frame-pixel-width) (frame-pixel-height)))
        (fullscreen (frame-parameter nil 'fullscreen))
        (file (make-temp-file "iron-tide-gui-"))
        session runtime arena saved)
    (unwind-protect
        (cl-labels
            ((ready () (and session (eq (etaf-gamekit-status session) 'ready)
                            (etaf-host-ref-size runtime 'tanks-board)))
             (state () (etaf-gamekit-view session :player))
             (text () (with-current-buffer (etaf-gamekit-buffer session)
                        (buffer-substring-no-properties (point-min) (point-max))))
             (press (ref) (etaf-focus runtime ref) (etaf-activate runtime))
             (action (id run settled &optional screenshot)
               (etaf-gui-verifier-action-create
                :id id :screenshot screenshot :settle-timeout 20
                :execute (lambda (_context) (funcall run))
                :settled-p (lambda (_context) (and (ready) (funcall settled)))))
             (key (id keys settled &optional screenshot)
               (action id (lambda () (switch-to-buffer (etaf-gamekit-buffer session))
                                     (execute-kbd-macro (kbd keys))) settled screenshot))
             (resize-actions (theme)
               (mapcar (lambda (spec)
                         (action (format "%s-%s" theme (car spec))
                                 (lambda () (etaf-tanks-gui--size (cadr spec) (caddr spec)))
                                 (lambda () (= (cdr (etaf-runtime-viewport runtime)) (window-body-height))) t))
                       '((wide 1200 44) (standard 900 42) (narrow 600 38)
                         (short 900 31) (minimum-clipping 420 22))))
             (fight ()
               (etaf-tanks-gui--size 900 42)
               (etaf-gamekit-action session "restart")
               (let ((end (+ (float-time) 4)))
                 (while (and (< (float-time) end) (not (ready))) (accept-process-output nil 0.01)))
               (unless (ready) (error "Restart did not acknowledge"))
               (press 'tanks-pause)
               (let ((end (+ (float-time) 18)))
                 (while (and (< (float-time) end)
                             (not (eq t (plist-get (state) :won)))
                             (not (eq t (plist-get (state) :lost))))
                   (when (ready)
                     (let* ((world (etaf-gamekit-view session :world))
                            (entities (plist-get world :entities)) (me (car entities)) direction)
                       (dolist (enemy (cdr entities))
                         (let ((dx (- (plist-get enemy :px) (plist-get me :px)))
                               (dy (- (plist-get enemy :py) (plist-get me :py))))
                           (cond ((< (abs dx) 0.3) (setq direction (if (< dy 0) "n" "s")))
                                 ((< (abs dy) 0.3) (setq direction (if (< dx 0) "w" "e"))))))
                       (when direction
                         (if (not (equal direction (plist-get (state) :facing)))
                             (press (intern (concat "tanks-aim-" direction)))
                           (unless (plist-get (etaf-runtime-host-props-for runtime 'tanks-fire) :disabled)
                             (press 'tanks-fire))))))
                   (accept-process-output nil 0.015)))))
          (etaf-gui-verifier-run
           (etaf-gui-verifier-scenario-create
            :name "iron-tide" :claim "Real-time physics, native controls, dual-theme appearance and resize"
            :initialize
            (lambda (context)
              (let ((etaf-tanks-appearance 'light)) (setq session (etaf-tanks-open)))
              (setq runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
              (etaf-gui-verifier-context-select-buffer context (etaf-gamekit-buffer session))
              (message nil))
            :invariants
            (lambda (_context)
              (let ((current (etaf-host-ref-size runtime 'tanks-board)))
                (unless arena (setq arena current))
                (append
                 (list (etaf-gui-verifier-assert "Arena keeps fixed metrics" (equal arena current))
                       (etaf-gui-verifier-assert "No backend or UI error" (not (etaf-gamekit-last-error session))))
                 (etaf-gui-verifier-line-height-assertions (etaf-gamekit-buffer session)))))
            :actions
            (append
             (resize-actions "light")
             (list (key "dark-theme" "t" (lambda () (string-match-p "浅色" (text))) t))
             (resize-actions "dark")
             (list
              (action "restore-size" (lambda () (etaf-tanks-gui--size 900 42))
                      (lambda () (= (cdr (etaf-runtime-viewport runtime)) 42)))
              (key "start" "p" (lambda () (eq :false (plist-get (state) :paused))))
              (key "fire" "SPC" (lambda () (> (plist-get (state) :shots) 0)) t)
              (key "pause" "p" (lambda () (eq t (plist-get (state) :paused))) t)
              (key "aim-north" "W" (lambda () (equal (plist-get (state) :facing) "n")))
              (key "resume" "p" (lambda () (eq :false (plist-get (state) :paused))))
              (key "drive-north" "w"
                   (lambda () (< (plist-get (car (plist-get (etaf-gamekit-view session :world) :entities)) :py) 10)))
              (key "stop" "x" (lambda () (eq :false (plist-get (state) :moving))))
              (action "pause-on-leave"
                      (lambda ()
                        (let ((other (generate-new-buffer " *tank focus acceptance*")) (end (+ (float-time) 4)))
                          (unwind-protect
                              (progn
                                (switch-to-buffer other) (redisplay t)
                                (while (and (< (float-time) end) (not (eq t (plist-get (state) :paused))))
                                  (accept-process-output nil 0.01)))
                            (switch-to-buffer (etaf-gamekit-buffer session)) (kill-buffer other))))
                      (lambda () (eq t (plist-get (state) :paused))))
              (key "help" "<f1>" (lambda () (string-match-p "驾驶与战斗" (text))) t)
              (key "close-help" "<escape>" (lambda () (not (string-match-p "驾驶与战斗" (text)))))
              (action "save"
                      (lambda ()
                        (setq saved (etaf-gamekit-observation session))
                        (execute-kbd-macro (vconcat (kbd "C-s C-a C-k") (string-to-vector file) (kbd "RET"))))
                      (lambda () (> (file-attribute-size (file-attributes file)) 0)))
              (key "restart" "n" (lambda () (= (plist-get (state) :shots) 0)))
              (action "load"
                      (lambda () (execute-kbd-macro (vconcat (kbd "C-o C-a C-k") (string-to-vector file) (kbd "RET"))))
                      (lambda ()
                        (and (eq t (plist-get (state) :paused))
                             (= (plist-get (state) :shots) (plist-get (plist-get saved :player) :shots)))))
              (action "victory" #'fight (lambda () (eq t (plist-get (state) :won))) t)
              (action "new-sortie" (lambda () (press 'tanks-new))
                      (lambda () (and (eq t (plist-get (state) :paused)) (= 3 (plist-get (state) :enemies)))))
              (action "defeat" (lambda () (press 'tanks-pause))
                      (lambda () (eq t (plist-get (state) :lost))) t))))
           directory))
      (when session (etaf-tanks-close session))
      (when (file-exists-p file) (delete-file file))
      (set-frame-size nil (car size) (cdr size) t)
      (set-frame-parameter nil 'fullscreen fullscreen))))

(provide 'etaf-tanks-gui-scenarios)
;;; etaf-tanks-gui-scenarios.el ends here
