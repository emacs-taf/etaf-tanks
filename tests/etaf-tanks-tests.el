;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-tests.el --- Battle rules, maps and application workflows
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Commentary:
;; Adapter scenarios drive `etaf-tanks-game' through GameKit operations;
;; application scenarios press the documented keys in the rendered buffer.
;;; Code:
(require 'ert)
(require 'etaf-tanks)

(defconst etaf-tanks-test--stages
  (expand-file-name "../native/godot/stages/" (file-name-directory (or load-file-name buffer-file-name)))
  "Bundled campaign maps.")

(defun etaf-tanks-test--map (name counts &rest rows)
  "Return map text called NAME with enemy COUNTS and ROWS."
  (concat "name: " name "\nenemies: " counts "\nmap:\n" (mapconcat #'identity rows "\n") "\n"))

(defconst etaf-tanks-test--duel
  (etaf-tanks-test--map "装甲对决" "0 0 0 1"
                        "@@@@EE@@@@@@" "@@@@EE@@@@@@" "@@@@..@@@@@@" "@@@@..@@@@@@"
                        "@@@@..@@@@@@" "@@@@..@@@@@@" "@@@@..@@@@@@" "@@@@..@@@@@@"
                        "@@@@PP@@@@@@" "@@@@PP@@@@@@" "@@@@@@@@@@@@" "@@@@@@@@@@@@"
                        "@@@@@@@@HH@@" "@@@@@@@@HH@@")
  "One armored enemy facing the player down a closed corridor.")

(defconst etaf-tanks-test--sentry
  (etaf-tanks-test--map "守卫" "1 0 0 0"
                        "EE@@@@@@@@@@" "EE@@@@@@@@@@" "@@@@@@@@@@@@" "@@@@@@@@@@@@"
                        "@@@@@@@@@@@@" "@@@@@@@@@@@@" "@@@@@@@@@@@@" "@@@@@@@@@@@@"
                        "@@@@PP@@@@@@" "@@@@PP@@@@@@" "@@@@HH@@@@@@" "@@@@HH@@@@@@")
  "A player parked directly above the base, with the enemy walled in.")

(defun etaf-tanks-test--stage (number)
  "Return the bundled campaign map NUMBER."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "%02d.txt" number) etaf-tanks-test--stages))
    (buffer-string)))

(defun etaf-tanks-test--settled-p (session predicate)
  "Whether SESSION is ready and PREDICATE holds."
  (and (eq (etaf-gamekit-status session) 'ready) (or (null predicate) (funcall predicate))))

(defun etaf-tanks-test--wait (session &optional predicate seconds each)
  "Await ready SESSION and PREDICATE for at most SECONDS, calling EACH meanwhile."
  (let ((end (+ (float-time) (or seconds 8))))
    (while (and (< (float-time) end)
                (not (memq (etaf-gamekit-status session) '(failed closed)))
                (not (etaf-tanks-test--settled-p session predicate)))
      (when each (funcall each))
      (accept-process-output nil 0.02)))
  (let ((status (etaf-gamekit-status session))
        (settled (etaf-tanks-test--settled-p session predicate)))
    (should (eq status 'ready)) (should settled)))

(defun etaf-tanks-test--view (session key)
  "Return KEY from SESSION's latest acknowledged observation.
The display view is published on a timer after the acknowledgement, so
reading it right after an action could still show the previous state."
  (plist-get (etaf-gamekit-observation session) key))

(defun etaf-tanks-test--phase-p (session &rest phases)
  "Return a predicate that holds while SESSION shows one of PHASES."
  (lambda () (member (etaf-tanks-test--view session :phase) phases)))

(defun etaf-tanks-test--start ()
  "Start an instance at the stage select, cleaning up if startup fails."
  (let* ((session (etaf-gamekit-start etaf-tanks-game))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))) good)
    (unwind-protect
        (progn
          (switch-to-buffer (etaf-gamekit-buffer session))
          (etaf-runtime-refit runtime 1300 50)
          ;; The connected application previews the selected stage.
          (etaf-tanks-test--wait session (lambda () (and (etaf-tanks-test--view session :size)
                                                         (etaf-host-ref-size runtime 'tanks-board))))
          (let ((error (etaf-gamekit-last-error session))) (should-not error))
          (setq good t)
          session)
      (unless good (etaf-tanks-close session)))))

(defun etaf-tanks-test--timer-errors (start)
  "Return timer failures logged to *Messages* after position START."
  (with-current-buffer (messages-buffer)
    (let (found)
      (save-excursion
        (goto-char (min start (point-max)))
        (while (re-search-forward "^Error running timer.*$" nil t)
          (push (match-string-no-properties 0) found)))
      (nreverse found))))

(defmacro etaf-tanks-test--with-sessions (names &rest body)
  "Run BODY with fresh instances bound to NAMES and private user files.
Rendering failures inside GameKit's publishing timer only reach *Messages*,
so the scenario also fails when one was logged."
  (declare (indent 1))
  `(let* ((root (make-temp-file "etaf-tanks-test-" t))
          (etaf-tanks-map-directory (file-name-as-directory (expand-file-name "maps" root)))
          (etaf-tanks-progress-file (expand-file-name "progress.eld" root))
          (messages (with-current-buffer (messages-buffer) (point-max)))
          ,@(mapcar (lambda (name) (list name nil)) names))
     (unwind-protect
         (progn ,@(mapcar (lambda (name) `(setq ,name (etaf-tanks-test--start))) names)
                ,@body
                (let ((failures (etaf-tanks-test--timer-errors messages))) (should-not failures)))
       ,@(mapcar (lambda (name) `(when ,name (etaf-tanks-close ,name))) names)
       (delete-directory root t))))

(defun etaf-tanks-test--act (session operation &optional arguments rejection)
  "Send OPERATION with ARGUMENTS; verify acknowledgement or the expected REJECTION."
  (etaf-gamekit-action session operation arguments)
  (etaf-tanks-test--wait session)
  (let ((failure (etaf-gamekit-last-error session)))
    (if rejection (should failure) (should-not failure))))

(defun etaf-tanks-test--begin (session map &rest arguments)
  "Begin a battle on MAP with ARGUMENTS and await its live phase.
Every battle opens with its intro, so waiting for it first keeps a previous
battle's published play phase from passing for the new one."
  (etaf-tanks-test--act session "begin" (append (list :map map) arguments))
  (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "intro"))
  (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "play")))

(defun etaf-tanks-test--units (session type)
  "Return SESSION's world units of TYPE."
  (seq-filter (lambda (unit) (equal (plist-get unit :type) type))
              (plist-get (etaf-tanks-test--view session :world) :units)))

(defun etaf-tanks-test--keys (session keys)
  "Press KEYS in SESSION's buffer, which the selected window shows."
  (switch-to-buffer (etaf-gamekit-buffer session))
  (execute-kbd-macro (kbd keys)))

(defun etaf-tanks-test--text (session)
  "Return SESSION's rendered text."
  (with-current-buffer (etaf-gamekit-buffer session)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun etaf-tanks-test--actor (session)
  "Return the player's position, facing and shot count."
  (let ((actor (etaf-tanks-test--view session :actor)))
    (list (plist-get actor :x) (plist-get actor :y) (plist-get actor :facing) (plist-get actor :shots))))

(defun etaf-tanks-test--stable (session)
  "Return SESSION's battle state without its event log."
  (let ((observation (etaf-gamekit-observation session)))
    (list (plist-get observation :phase) (plist-get observation :paused) (plist-get observation :hud)
          (plist-get observation :actor) (plist-get observation :world))))

(ert-deftest etaf-tanks-maps-are-validated-before-play ()
  "Previews report map defects, and an invalid map cannot start a battle."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--act session "menu" (list :map etaf-tanks-test--duel))
    (let ((problem (etaf-tanks-test--view session :map_error))
          (size (etaf-tanks-test--view session :size)))
      (should (equal problem "")) (should (equal size '(12 14))))
    (let ((baseless (string-replace "HH" "@@" etaf-tanks-test--duel)))
      (etaf-tanks-test--act session "menu" (list :map baseless))
      (let ((problem (etaf-tanks-test--view session :map_error)))
        (should (string-match-p "基地" problem)))
      (etaf-tanks-test--act session "begin" (list :map baseless) t)
      (let ((phase (etaf-tanks-test--view session :phase))) (should (equal phase "menu"))))
    ;; Undersized maps are reported without a preview the session cannot show.
    (etaf-tanks-test--act session "menu"
                          (list :map (etaf-tanks-test--map "小" "1 0 0 0" "EE.." "EE.." "PPHH" "PPHH")))
    (let ((problem (etaf-tanks-test--view session :map_error))
          (size (etaf-tanks-test--view session :size)))
      (should (string-match-p "尺寸" problem)) (should-not size))
    (let ((status (etaf-gamekit-status session))) (should (eq status 'ready)))))

(ert-deftest etaf-tanks-settings-and-difficulty-are-validated ()
  "Out-of-range settings are rejected; difficulty sets the starting lives."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--act session "settings" '(:speed 2.5) t)
    (etaf-tanks-test--act session "settings" '(:frame_rate 90) t)
    (etaf-tanks-test--act session "settings" '(:speed 2.0 :player_speed 0.5 :frame_rate 60))
    (let ((settings (etaf-tanks-test--view session :settings)))
      (should (= (plist-get settings :speed) 2.0))
      (should (= (plist-get settings :player_speed) 0.5))
      (should (= (plist-get settings :frame_rate) 60)))
    (etaf-tanks-test--begin session (etaf-tanks-test--stage 1) :difficulty "easy" :seed 3)
    (let ((lives (plist-get (etaf-tanks-test--view session :hud) :lives))) (should (= lives 5)))
    (etaf-tanks-test--begin session (etaf-tanks-test--stage 1) :difficulty "hard" :seed 3)
    (let ((lives (plist-get (etaf-tanks-test--view session :hud) :lives))) (should (= lives 3)))
    (etaf-tanks-test--act session "begin" (list :map (etaf-tanks-test--stage 1) :difficulty "insane") t)))

(ert-deftest etaf-tanks-losing-the-base-ends-the-battle ()
  "A shell that reaches the eagle base loses the battle, whoever fired it."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--begin session etaf-tanks-test--sentry :difficulty "easy" :seed 1)
    (etaf-tanks-test--act session "aim" '(:direction "s"))
    (etaf-tanks-test--act session "fire")
    (etaf-tanks-test--wait session (lambda () (eq :false (plist-get (etaf-tanks-test--view session :hud) :base))) 3)
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "over") 6)
    (let ((cleared (plist-get (etaf-tanks-test--view session :tally) :cleared))) (should (eq cleared :false)))))

(ert-deftest etaf-tanks-armored-enemies-take-four-hits ()
  "An armored tank loses one armor per hit and scores only when destroyed."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--begin session etaf-tanks-test--duel :difficulty "easy" :seed 5)
    (let ((seen nil) (next 0.0))
      (etaf-tanks-test--wait
       session (lambda () (equal (etaf-tanks-test--view session :phase) "cleared")) 30
       (lambda ()
         (dolist (unit (etaf-tanks-test--units session "armor"))
           (cl-pushnew (plist-get unit :armour) seen))
         (when (> (float-time) next)
           (setq next (+ (float-time) 0.1))
           (when (eq (etaf-gamekit-status session) 'ready)
             (etaf-gamekit-action session "fire")))))
      ;; Shells already in flight can hit the tank in its first published frame.
      (should (member (sort seen #'<) '((1 2 3) (1 2 3 4)))))
    (let ((tally (etaf-tanks-test--view session :tally)))
      (should (equal (plist-get tally :kills) '(0 0 0 1)))
      (should (eq (plist-get tally :cleared) t)))))

(ert-deftest etaf-tanks-world-runs-without-input-and-pauses-atomically ()
  "Enemies advance on Godot's clock without commands and freeze while paused."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--begin session (etaf-tanks-test--stage 1) :difficulty "normal" :seed 11)
    (etaf-tanks-test--wait session (lambda () (cdr (plist-get (etaf-tanks-test--view session :world) :units))) 8)
    (let ((before (etaf-tanks-test--stable session)))
      (etaf-tanks-test--wait session (lambda () (not (equal before (etaf-tanks-test--stable session))))))
    (etaf-tanks-test--act session "pause")
    (let ((frozen (etaf-tanks-test--stable session)) (until (+ (float-time) 0.4)))
      (while (< (float-time) until) (accept-process-output nil 0.02))
      (should (equal frozen (etaf-tanks-test--stable session)))
      ;; Paused input is acknowledged without moving the world.
      (etaf-tanks-test--act session "drive" '(:direction "e"))
      (etaf-tanks-test--act session "fire")
      (should (equal frozen (etaf-tanks-test--stable session)))
      ;; An explicit pause state is idempotent; a malformed one is rejected.
      (etaf-tanks-test--act session "pause" '(:paused t))
      (etaf-tanks-test--act session "pause" '(:paused 1) t)
      (should (equal frozen (etaf-tanks-test--stable session)))
      (etaf-tanks-test--act session "pause" '(:paused :false))
      (should (eq (etaf-tanks-test--view session :paused) :false)))))

(ert-deftest etaf-tanks-snapshots-restore-paused-with-atomic-rejection ()
  "A snapshot restores the battle paused; malformed files preserve it."
  (etaf-tanks-test--with-sessions (session)
    (let ((file (make-temp-file "etaf-tanks-save-" nil ".json"))
          (broken (make-temp-file "etaf-tanks-broken-" nil ".json" "{\"format\":")))
      (unwind-protect
          (progn
            (etaf-tanks-test--begin session (etaf-tanks-test--stage 2) :difficulty "easy" :seed 9)
            (etaf-tanks-test--act session "pause")
            (let ((saved (etaf-tanks-test--stable session)))
              (etaf-tanks-test--act session "save" (list :path file))
              (etaf-tanks-test--act session "pause")
              (etaf-tanks-test--wait session (lambda () (not (equal saved (etaf-tanks-test--stable session)))))
              (etaf-tanks-test--act session "load" (list :path file))
              (let ((restored (etaf-tanks-test--stable session)))
                (should (equal (nth 1 restored) t))
                (should (equal (nth 3 restored) (nth 3 saved)))
                (should (equal (plist-get (nth 2 restored) :lives) (plist-get (nth 2 saved) :lives)))
                (should (equal (plist-get (nth 4 restored) :terrain) (plist-get (nth 4 saved) :terrain)))
                (etaf-tanks-test--act session "load" (list :path broken) t)
                (etaf-tanks-test--act session "load" (list :path (concat file ".missing")) t)
                (should (equal restored (etaf-tanks-test--stable session))))))
        (delete-file file) (delete-file broken)))))

(ert-deftest etaf-tanks-battles-are-independent ()
  "One live battle cannot advance a second paused battlefield."
  (etaf-tanks-test--with-sessions (first second)
    (etaf-tanks-test--begin first (etaf-tanks-test--stage 1) :seed 1)
    (etaf-tanks-test--begin second (etaf-tanks-test--stage 1) :seed 1)
    (etaf-tanks-test--act second "pause")
    (let ((before (etaf-tanks-test--stable second)) (moving (etaf-tanks-test--stable first)))
      (etaf-tanks-test--wait first (lambda () (not (equal moving (etaf-tanks-test--stable first)))))
      (should (equal before (etaf-tanks-test--stable second))))))

(ert-deftest etaf-tanks-keys-drive-aim-fire-and-pause-a-campaign ()
  "The named stage select starts a campaign that the documented keys control."
  (etaf-tanks-test--with-sessions (session)
    (let ((title (plist-get (etaf-gamekit-game-info session) :title))
          (heading-present (string-match-p "坦克大战" (etaf-tanks-test--text session))))
      (should (equal title "坦克大战"))
      (should heading-present))
    (should (string-match-p "第 1 关" (etaf-tanks-test--text session)))
    (etaf-tanks-test--keys session "g")
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "play"))
    (let ((start (etaf-tanks-test--actor session)))
      (dotimes (_ 6) (etaf-tanks-test--keys session "<right>") (accept-process-output nil 0.1))
      (etaf-tanks-test--wait session (lambda () (> (car (etaf-tanks-test--actor session)) (car start))))
      (let ((facing (nth 2 (etaf-tanks-test--actor session)))) (should (equal facing "e")))
      (etaf-tanks-test--keys session "S-<up>")
      (etaf-tanks-test--wait session (lambda () (equal (nth 2 (etaf-tanks-test--actor session)) "n")))
      (etaf-tanks-test--keys session "f")
      (etaf-tanks-test--wait session (lambda () (> (nth 3 (etaf-tanks-test--actor session)) (nth 3 start)))))
    (etaf-tanks-test--keys session "p")
    (etaf-tanks-test--wait session (lambda () (eq t (etaf-tanks-test--view session :paused))))
    (etaf-tanks-test--wait session (lambda () (string-match-p "继续 · P" (etaf-tanks-test--text session))))
    ;; A paused battle is left without confirmation.
    (etaf-tanks-test--keys session "m")
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "menu"))))

(ert-deftest etaf-tanks-editor-paints-saves-and-test-plays ()
  "Editing a stage saves a custom map that test play and the catalog use."
  (etaf-tanks-test--with-sessions (session)
    (etaf-tanks-test--keys session "e")
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "edit"))
    (etaf-tanks-test--keys session "<right> <right> <down> 3 f")
    (etaf-tanks-test--keys session "C-s RET")
    (let* ((file (expand-file-name "前哨-改.txt" etaf-tanks-map-directory))
           (text (and (file-exists-p file) (with-temp-buffer (insert-file-contents file) (buffer-string)))))
      (should (string-match-p "^name: 前哨 改$" text))
      (should (string-match-p "^map:\n.*\n..@" text)))
    (etaf-tanks-test--keys session "p")
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "intro" "play"))
    (etaf-tanks-test--keys session "m yes RET")
    (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "edit"))
    (etaf-tanks-test--keys session "m")
    (etaf-tanks-test--wait session (lambda () (and (equal (etaf-tanks-test--view session :phase) "menu")
                                                   (string-match-p "前哨 改" (etaf-tanks-test--text session)))))))

(ert-deftest etaf-tanks-themes-and-resize-preserve-paused-battle ()
  "Appearance and resizing preserve the battlefield, state and keyboard focus."
  (etaf-tanks-test--with-sessions (session)
    (let ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
      (etaf-tanks-test--keys session "g")
      (etaf-tanks-test--wait session (etaf-tanks-test--phase-p session "play"))
      (etaf-tanks-test--keys session "p")
      (etaf-tanks-test--wait session (lambda () (eq t (etaf-tanks-test--view session :paused))))
      (let ((before (etaf-tanks-test--stable session)))
        (dolist (width '(700 1300))
          (etaf-tanks-test--keys session "t")
          (etaf-runtime-refit runtime width 40)
          (etaf-tanks-test--wait session (lambda () (etaf-host-ref-size runtime 'tanks-board)))
          (let ((after (etaf-tanks-test--stable session)) (focus (etaf-focused-host-ref runtime)))
            (should (equal before after)) (should (eq focus 'tanks-board))))))))

(provide 'etaf-tanks-tests)
;;; etaf-tanks-tests.el ends here
