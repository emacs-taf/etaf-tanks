;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-board.el --- Battlefield canvas: native frames or a text grid
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Godot composes the battlefield at the original 8-pixel block resolution and
;; writes one PNG per changed frame.  A graphical display shows that frame
;; scaled by whole or half steps without smoothing, sliced into character rows
;; and replaced through the Text Host's retained content route, so a moving
;; battle never pays for an ordinary publication.  Text displays draw the
;; published world description as two characters per block instead.

;;; Code:
(require 'cl-lib)
(require 'etaf-ui)

(defconst etaf-tanks--block-pixels 8
  "Native pixels per map block.")

(defconst etaf-tanks--flush-batch 30
  "Frames shown before older frame images leave Emacs's image cache.
Evicting an image garbages the whole frame for one full redisplay, so frames
are released together instead of once per frame.")

(defun etaf-tanks--metrics (graphic)
  "Return the opening frame's character metrics; GRAPHIC selects frames."
  (list :graphic graphic :char-width (frame-char-width) :line-height (frame-char-height)
        :half-steps (and graphic (fboundp 'frame-scale-factor) (>= (frame-scale-factor) 2))))

(defun etaf-tanks--fit-scale (size metrics width height)
  "Return the largest scale showing SIZE blocks within WIDTH x HEIGHT pixels.
Scales are whole numbers, or halves on high-density displays where a half
step still maps every native pixel to whole device pixels.  Below the first
scale the battlefield keeps scale 1 and the viewport clips it."
  (let* ((native-width (* (car size) etaf-tanks--block-pixels))
         (native-height (* (cadr size) etaf-tanks--block-pixels))
         (step (if (plist-get metrics :half-steps) 0.5 1))
         (scale 1))
    (cl-loop for candidate from 1 to 6 by step
             when (and (<= (* native-width candidate) width) (<= (* native-height candidate) height))
             do (setq scale candidate))
    scale))

(defun etaf-tanks--board-geometry (size metrics scale)
  "Return the canvas geometry for SIZE blocks at SCALE under METRICS."
  (if (plist-get metrics :graphic)
      (let ((width (round (* (car size) etaf-tanks--block-pixels scale)))
            (height (round (* (cadr size) etaf-tanks--block-pixels scale))))
        (list :graphic t :scale scale :pixel-width width :pixel-height height
              :columns (ceiling width (float (plist-get metrics :char-width)))
              :rows (ceiling height (float (plist-get metrics :line-height)))
              :line-height (plist-get metrics :line-height)))
    (list :graphic nil :columns (* 2 (car size)) :rows (cadr size))))

(defun etaf-tanks--image-placement ()
  "Return how image slices sit in a line: (PERCENT ASCENT FONT-HEIGHT).
PERCENT keeps a full slice one line tall.  ASCENT is the pixel ascent such a
slice gives its line and FONT-HEIGHT the default font height that scales a
`raise' display specification; both are nil when the font is unknown."
  (let* ((height (frame-char-height))
         (font (and (display-graphic-p) (face-font 'default)))
         (info (and font (font-info font)))
         (ascent (and (vectorp info) (> (length info) 9) (aref info 8)))
         (descent (and (vectorp info) (> (length info) 9) (aref info 9)))
         (font-height (and (vectorp info) (> (length info) 3) (aref info 3))))
    (if (and (numberp ascent) (numberp descent) (numberp font-height)
             (> height 0) (> ascent 0) (>= descent 0) (> font-height 0))
        (let ((percent (min 100 (max 1 (ceiling (* 100.0 (/ (float ascent) height)))))))
          (list percent (max ascent (truncate (* height (/ percent 100.0)))) font-height))
      (list 82 nil nil))))

(defun etaf-tanks--slice-raise (placement height)
  "Return the `raise' factor lifting a slice HEIGHT pixels tall to the line top.
PLACEMENT comes from `etaf-tanks--image-placement'.  Emacs gives a partial
slice only its proportional ascent, which would leave a gap above it."
  (pcase-let ((`(,percent ,ascent ,font-height) placement))
    (when ascent
      (let ((lift (- ascent (truncate (* height (/ percent 100.0))))))
        ;; Emacs truncates the scaled offset, so aim half a pixel past LIFT.
        (and (> lift 0) (/ (+ lift 0.5) font-height))))))

;;; Text grid

(defconst etaf-tanks--text-palettes
  '((dark :ground ("#101010" . "#101010") :brick ("#E07A3A" . "#5A2410") :steel ("#E8E8E8" . "#8A8A8A")
          :water ("#9CC4FF" . "#1E46B4") :forest ("#9AE05A" . "#1C5A1C") :ice ("#FFFFFF" . "#9FBCCB")
          :base ("#F0F0F0" . "#303030") :ruin ("#A0A0A0" . "#303030") :player ("#FFD23C" . "#101010")
          :enemy ("#E8E8E8" . "#101010") :armor ("#FF8A8A" . "#101010") :shell ("#FFFFFF" . "#101010")
          :bonus ("#FF6060" . "#FFFFFF") :cursor ("#101010" . "#FFD23C"))
    (light :ground ("#F2EFE6" . "#F2EFE6") :brick ("#F7B57A" . "#A6461C") :steel ("#4A4A4A" . "#B8B8B8")
           :water ("#E0ECFF" . "#3C6AD2") :forest ("#E4FFD2" . "#3C8A2E") :ice ("#7A8F9A" . "#DCEAF0")
           :base ("#202020" . "#D8D2C4") :ruin ("#7A7A7A" . "#D8D2C4") :player ("#B07A00" . "#F2EFE6")
           :enemy ("#3A3A3A" . "#F2EFE6") :armor ("#C03030" . "#F2EFE6") :shell ("#202020" . "#F2EFE6")
           :bonus ("#FFFFFF" . "#E04040") :cursor ("#F2EFE6" . "#202020")))
  "Foreground and background pairs for the text battlefield.")

(defconst etaf-tanks--terrain-glyphs
  '((?. "  " :ground) (?# "▓▓" :brick) (?@ "██" :steel) (?~ "≈≈" :water) (?* "♣♣" :forest)
    (?= "░░" :ice) (?H "◆◆" :base) (?X "▒▒" :ruin) (?P "  " :ground) (?E "··" :ground))
  "Two-character text cell and palette role of each map symbol.")

(defun etaf-tanks--facing-glyph (facing)
  "Return the text glyph for FACING."
  (pcase facing ("n" "▲▲") ("e" "▶▶") ("s" "▼▼") (_ "◀◀")))

(defun etaf-tanks--text-board (rows theme &optional world cursor)
  "Return text drawing terrain ROWS in THEME with WORLD units and CURSOR.
ROWS are map strings; WORLD is the published world plist; CURSOR is
(X Y SIZE) in blocks.  Each block is two characters; a tank covers 2x2
blocks.  Forest hides tanks below it, as on the graphical canvas."
  (let* ((palette (alist-get theme etaf-tanks--text-palettes))
         (height (length rows)) (width (length (car rows)))
         (cells (make-vector (* width height) nil)))
    (cl-loop for row in rows for y from 0 do
             (dotimes (x width)
               (let ((glyph (assq (aref row x) etaf-tanks--terrain-glyphs)))
                 (aset cells (+ (* y width) x) (cons (cadr glyph) (nth 2 glyph))))))
    (let ((put (lambda (x y text role)
                 (when (and (<= 0 x) (< x width) (<= 0 y) (< y height)
                            (not (eq (cdr (aref cells (+ (* y width) x))) :forest)))
                   (aset cells (+ (* y width) x) (cons text role))))))
      (dolist (unit (plist-get world :units))
        (let ((x (round (plist-get unit :x))) (y (round (plist-get unit :y)))
              (glyph (etaf-tanks--facing-glyph (plist-get unit :facing)))
              (role (cond ((equal (plist-get unit :kind) "player") :player)
                          ((eq t (plist-get unit :bonus)) :bonus)
                          ((equal (plist-get unit :type) "armor") :armor)
                          (t :enemy))))
          (dotimes (dy 2) (dotimes (dx 2) (funcall put (+ x dx) (+ y dy) glyph role)))))
      (dolist (shell (plist-get world :shells))
        (funcall put (floor (plist-get shell :x)) (floor (plist-get shell :y)) "• " :shell))
      (when-let* ((bonus (plist-get world :bonus)))
        (let ((x (floor (plist-get bonus :x))) (y (floor (plist-get bonus :y))))
          (dotimes (dy 2) (dotimes (dx 2) (funcall put (+ x dx) (+ y dy) "★★" :bonus))))))
    (when cursor
      (cl-destructuring-bind (cx cy size) cursor
        (dotimes (dy size)
          (dotimes (dx size)
            (let ((x (+ cx dx)) (y (+ cy dy)))
              (when (and (< x width) (< y height))
                (setcdr (aref cells (+ (* y width) x)) :cursor)))))))
    (mapconcat
     (lambda (y)
       (let ((parts nil) (run nil) (role nil))
         (dotimes (x width)
           (let ((cell (aref cells (+ (* y width) x))))
             (unless (eq (cdr cell) role)
               (when run (push (etaf-tanks--text-run (apply #'concat (nreverse run)) role palette) parts))
               (setq run nil role (cdr cell)))
             (push (car cell) run)))
         (push (etaf-tanks--text-run (apply #'concat (nreverse run)) role palette) parts)
         (apply #'concat (nreverse parts))))
     (number-sequence 0 (1- height)) "\n")))

(defun etaf-tanks--text-run (text role palette)
  "Paint TEXT with ROLE's colors from PALETTE."
  (let ((colors (plist-get palette role)))
    (propertize text 'face (list :foreground (car colors) :background (cdr colors)))))

;;; Canvas

(cl-defstruct (etaf-tanks--canvas (:constructor etaf-tanks--canvas-make) (:copier nil))
  "Mutable presentation state of one mounted board."
  runtime ref cell geometry placement frame shown)

(defun etaf-tanks--canvas-content (canvas)
  "Build CANVAS's text for its current frame and geometry."
  (let* ((geometry (etaf-tanks--canvas-geometry canvas))
         (frame (etaf-tanks--canvas-frame canvas))
         (rows (plist-get geometry :rows)))
    (if (not (and frame (plist-get geometry :graphic)))
        (mapconcat #'identity (make-list rows " ") "\n")
      (let* ((width (plist-get geometry :pixel-width)) (height (plist-get geometry :pixel-height))
             (line (plist-get geometry :line-height))
             ;; The frame id makes every spec distinct: Godot reuses a small
             ;; ring of files, and Emacs caches decoded images by spec.
             (image (create-image (plist-get frame :path) 'png nil
                                  :width width :height height :transform-smoothing nil
                                  :ascent (car (etaf-tanks--canvas-placement canvas))
                                  :etaf-tanks-frame (plist-get frame :id))))
        (push image (etaf-tanks--canvas-shown canvas))
        (mapconcat (lambda (row)
                     (let* ((y (* row line)) (slice (min line (- height y)))
                            (raise (and (< 0 slice line)
                                        (etaf-tanks--slice-raise (etaf-tanks--canvas-placement canvas) slice))))
                       (if (>= y height) " "
                         (propertize " " 'display
                                     (if raise
                                         (list (list 'raise raise) (list 'slice 0 y width slice) image)
                                       (list (list 'slice 0 y width slice) image))))))
                   (number-sequence 0 (1- rows)) "\n")))))

(defun etaf-tanks--canvas-release (canvas &optional all)
  "Evict CANVAS's shown frame images, keeping the newest unless ALL."
  (let ((shown (etaf-tanks--canvas-shown canvas)))
    (dolist (image (if all shown (cdr shown)))
      (image-flush image))
    (setf (etaf-tanks--canvas-shown canvas) (if all nil (and shown (list (car shown)))))))

(defun etaf-tanks--canvas-present (canvas)
  "Replace CANVAS's mounted content with its current frame."
  (let ((runtime (etaf-tanks--canvas-runtime canvas)))
    (when (and runtime (etaf-runtime-mounted-p runtime))
      (let ((content (etaf-tanks--canvas-content canvas)))
        (setcar (etaf-tanks--canvas-cell canvas) content)
        (etaf-runtime-update-host-content runtime (etaf-tanks--canvas-ref canvas) content)
        (when (> (length (etaf-tanks--canvas-shown canvas)) etaf-tanks--flush-batch)
          (etaf-tanks--canvas-release canvas))))))

(defvar etaf-tanks--board-counter 0
  "Counter giving each mounted board a session-unique Host id.")

(etaf-define-component etaf-tanks--board (&key frame text geometry background)
  "Show FRAME (graphic) or TEXT (text displays) in a canvas of GEOMETRY.
FRAME, TEXT and GEOMETRY are reactive sources.  New frames, text and sizes
replace only this Host's content after the render that changed its box."
  :bindings ((content-ref (etaf-local-ref 'content))
             (content-id (format "etaf-tanks-board-%d" (cl-incf etaf-tanks--board-counter)))
             (canvas (etaf-tanks--canvas-make :ref content-ref :cell (cons " " nil)
                                              :placement (etaf-tanks--image-placement))))
  :setup
  (let ((graphic (plist-get (etaf-value geometry) :graphic)))
    ;; A remounted board starts from the latest frame: Godot publishes only
    ;; on change, so a static menu preview may never send another one.
    (setf (etaf-tanks--canvas-geometry canvas) (etaf-value geometry))
    (if graphic
        (progn (setf (etaf-tanks--canvas-frame canvas) (etaf-value frame))
               (setcar (etaf-tanks--canvas-cell canvas) (etaf-tanks--canvas-content canvas)))
      (setcar (etaf-tanks--canvas-cell canvas) (or (etaf-value text) " ")))
    (etaf-on-mounted (lambda ()
                       (setf (etaf-tanks--canvas-runtime canvas) (etaf-current-runtime))
                       (when graphic (etaf-tanks--canvas-present canvas))))
    (etaf-on-unmounted (lambda ()
                         (etaf-tanks--canvas-release canvas t)
                         (setf (etaf-tanks--canvas-runtime canvas) nil)))
    (if graphic
        (progn
          ;; Resizing renders the box first; the content follows it.
          (etaf-watch geometry (lambda (next _old)
                                 (setf (etaf-tanks--canvas-geometry canvas) next)
                                 (etaf-tanks--canvas-present canvas))
                      :flush 'post :test #'equal)
          (etaf-watch frame (lambda (next _old)
                              (setf (etaf-tanks--canvas-frame canvas) next)
                              (etaf-tanks--canvas-present canvas))
                      :flush 'post :test #'equal))
      (etaf-watch text (lambda (next _old)
                         (let ((runtime (etaf-tanks--canvas-runtime canvas)))
                           (setcar (etaf-tanks--canvas-cell canvas) (or next " "))
                           (when (and runtime (etaf-runtime-mounted-p runtime))
                             (etaf-runtime-update-host-content runtime content-ref (or next " ")))))
                  :flush 'post :test #'equal)))
  :view
  (box :ref 'tanks-board :width (list 'ch (plist-get (etaf-value geometry) :columns))
       :height (list 'lh (plist-get (etaf-value geometry) :rows))
       :position 'static :left '(px 0) :top '(lh 0) :z-index 0
       :wrap-mode 'none :overflow 'hidden :background-color background
       :tab-index 0 :role 'region :aria-label "战场"
    (text :ref content-ref :id content-id (expr (car (etaf-tanks--canvas-cell canvas))))))

(provide 'etaf-tanks-board)
;;; etaf-tanks-board.el ends here
