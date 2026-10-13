;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-board.el --- Battlefield canvas: native frames or a text grid
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Godot draws the battlefield at the display's device resolution and writes
;; it as strips one text line tall, each changed strip as a new numbered PNG.
;; A graphical display shows every strip as the image of one line of the
;; board's Text Host and replaces only the images whose strip changed, so a
;; moving battle decodes a few lines instead of the whole field.  Text
;; displays draw the published world description as two characters per
;; block instead.

;;; Code:
(require 'cl-lib)
(require 'etaf-ui)

(defconst etaf-tanks--block-sizes '((small . 12) (medium . 16) (large . 20))
  "Preferred logical pixels per map block for each board size.")

(defconst etaf-tanks--smallest-block 10
  "Smallest block in logical pixels; a narrower window clips the board.")

(defconst etaf-tanks--flush-batch 10
  "Frames shown before replaced strip images leave Emacs's image cache.
Evicting an image garbages the whole frame for one full redisplay, so the
replaced images of several frames are released together.")

(defun etaf-tanks--metrics (graphic)
  "Return reactive display metrics; GRAPHIC selects native frames.
DENSITY is the device pixels per logical pixel the native canvas draws for."
  (append (list :graphic graphic
                :density (if (and graphic (fboundp 'frame-scale-factor))
                             (max 1 (round (frame-scale-factor))) 1))
          (etaf-display-metrics)))

(defun etaf-tanks--fit-block (size preferred width height)
  "Return the logical block pixels showing SIZE blocks within WIDTH x HEIGHT.
The block starts at PREFERRED and shrinks by two pixels until the board fits
or reaches `etaf-tanks--smallest-block', below which the viewport clips."
  (let ((block preferred))
    (while (and (> block etaf-tanks--smallest-block)
                (or (> (* (car size) block) width) (> (* (cadr size) block) height)))
      (cl-decf block 2))
    block))

(defun etaf-tanks--board-geometry (size metrics block)
  "Return the canvas geometry for SIZE blocks of BLOCK pixels under METRICS.
DEVICE-BLOCK and DEVICE-LINE are what the native canvas draws a block and a
strip in; both are even, so half blocks stay on whole device pixels."
  (if (plist-get metrics :graphic)
      (let* ((density (plist-get metrics :density)) (line (plist-get metrics :line-height))
             (width (* (car size) block)) (height (* (cadr size) block)))
        (list :graphic t :block block :density density
              :device-block (* block density) :device-line (* line density)
              :pixel-width width :pixel-height height
              :columns (ceiling width (float (plist-get metrics :char-width)))
              :rows (ceiling height (float line)) :line-height line
              :ascent (plist-get metrics :ascent)))
    (list :graphic nil :columns (* 2 (car size)) :rows (cadr size))))

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
  "Mutable presentation state of one mounted board.
IMAGES and SERIALS hold each strip's image and file version, CELLS the
line text showing it; SHOWN is the (BLOCK LINE WIDTH ASCENT) presentation.
RETIRED images wait for the next batched cache flush after PRESENTED frames."
  runtime ref cell geometry directory ascent frame shown images serials cells retired (presented 0))

(defun etaf-tanks--canvas-matches-p (canvas frame)
  "Whether FRAME was drawn for CANVAS's current geometry.
After a resize Godot needs one frame to adopt the new block and line; until
then the board keeps showing the strips it has."
  (let ((geometry (etaf-tanks--canvas-geometry canvas)))
    (and frame (plist-get geometry :graphic)
         (eql (plist-get frame :block) (plist-get geometry :device-block))
         (eql (plist-get frame :line) (plist-get geometry :device-line))
         (eql (plist-get frame :width) (* (plist-get geometry :pixel-width) (plist-get geometry :density))))))

(defun etaf-tanks--canvas-adopt (canvas)
  "Load the strips of CANVAS's frame that changed; return non-nil if any did.
A strip whose file is gone keeps its previous image: Godot retires a file
only after writing newer versions, which a later frame then names."
  (let ((frame (etaf-tanks--canvas-frame canvas)))
    (when (etaf-tanks--canvas-matches-p canvas frame)
      (let* ((strips (plist-get frame :strips)) (count (length strips))
             (shape (list (plist-get frame :block) (plist-get frame :line)
                          (plist-get frame :width) (etaf-tanks--canvas-ascent canvas)))
             (scale (/ 1.0 (plist-get (etaf-tanks--canvas-geometry canvas) :density)))
             (directory (etaf-tanks--canvas-directory canvas))
             (changed nil))
        (unless (and (equal shape (etaf-tanks--canvas-shown canvas))
                     (= count (length (etaf-tanks--canvas-images canvas))))
          (etaf-tanks--canvas-retire canvas)
          (setf (etaf-tanks--canvas-shown canvas) shape
                (etaf-tanks--canvas-images canvas) (make-vector count nil)
                (etaf-tanks--canvas-serials canvas) (make-vector count nil)
                (etaf-tanks--canvas-cells canvas) (make-vector count " ")))
        (let ((images (etaf-tanks--canvas-images canvas))
              (serials (etaf-tanks--canvas-serials canvas))
              (cells (etaf-tanks--canvas-cells canvas)))
          (cl-loop for serial in strips for row from 0 do
                   (unless (eql serial (aref serials row))
                     (let ((file (expand-file-name (format "%d-%d.png" row serial) directory)))
                       (when (file-exists-p file)
                         (when (aref images row)
                           (push (aref images row) (etaf-tanks--canvas-retired canvas)))
                         (let ((image (create-image file 'png nil :scale scale
                                                    :ascent (etaf-tanks--canvas-ascent canvas))))
                           (aset images row image)
                           (aset serials row serial)
                           (aset cells row (propertize " " 'display image))
                           (setq changed t)))))))
        changed))))

(defun etaf-tanks--canvas-retire (canvas)
  "Schedule every strip image CANVAS shows for eviction."
  (let ((images (etaf-tanks--canvas-images canvas)))
    (when images
      (cl-loop for image across images
               when image do (push image (etaf-tanks--canvas-retired canvas))))
    (setf (etaf-tanks--canvas-images canvas) nil (etaf-tanks--canvas-serials canvas) nil
          (etaf-tanks--canvas-cells canvas) nil (etaf-tanks--canvas-shown canvas) nil)))

(defun etaf-tanks--canvas-release (canvas)
  "Evict CANVAS's retired strip images from Emacs's image cache."
  (dolist (image (etaf-tanks--canvas-retired canvas))
    (image-flush image))
  (setf (etaf-tanks--canvas-retired canvas) nil))

(defun etaf-tanks--canvas-content (canvas)
  "Return CANVAS's text: one strip image per line, or blank lines."
  (let ((cells (etaf-tanks--canvas-cells canvas)))
    (if (and cells (> (length cells) 0))
        (mapconcat #'identity cells "\n")
      (mapconcat #'identity
                 (make-list (max 1 (plist-get (etaf-tanks--canvas-geometry canvas) :rows)) " ") "\n"))))

(defun etaf-tanks--canvas-present (canvas)
  "Replace CANVAS's mounted content with its current strips."
  (let ((runtime (etaf-tanks--canvas-runtime canvas)))
    (when (and runtime (etaf-runtime-mounted-p runtime))
      (let ((content (etaf-tanks--canvas-content canvas)))
        (setcar (etaf-tanks--canvas-cell canvas) content)
        (etaf-runtime-update-host-content runtime (etaf-tanks--canvas-ref canvas) content)
        (when (>= (cl-incf (etaf-tanks--canvas-presented canvas)) etaf-tanks--flush-batch)
          (setf (etaf-tanks--canvas-presented canvas) 0)
          (etaf-tanks--canvas-release canvas))))))

(defvar etaf-tanks--board-counter 0
  "Counter giving each mounted board a session-unique Host id.")

(etaf-define-component etaf-tanks--board (&key frame text geometry directory background)
  "Show FRAME (graphic) or TEXT (text displays) in a canvas of GEOMETRY.
FRAME, TEXT and GEOMETRY are reactive sources; FRAME names strip files in
DIRECTORY.  New strips, text and sizes replace only this Host's content
after the render that changed its box."
  :bindings ((content-ref (etaf-local-ref 'content))
             (content-id (format "etaf-tanks-board-%d" (cl-incf etaf-tanks--board-counter)))
             (canvas (etaf-tanks--canvas-make :ref content-ref :cell (cons " " nil) :directory directory
                                              :ascent (plist-get (etaf-value geometry) :ascent))))
  :setup
  (let ((graphic (plist-get (etaf-value geometry) :graphic)))
    ;; A remounted board starts from the latest frame: Godot publishes only
    ;; on change, so a static menu preview may never send another one.
    (setf (etaf-tanks--canvas-geometry canvas) (etaf-value geometry))
    (if graphic
        (progn (setf (etaf-tanks--canvas-frame canvas) (etaf-value frame))
               (etaf-tanks--canvas-adopt canvas)
               (setcar (etaf-tanks--canvas-cell canvas) (etaf-tanks--canvas-content canvas)))
      (setcar (etaf-tanks--canvas-cell canvas) (or (etaf-value text) " ")))
    (etaf-on-mounted (lambda ()
                       (setf (etaf-tanks--canvas-runtime canvas) (etaf-current-runtime))
                       (when graphic (etaf-tanks--canvas-present canvas))))
    (etaf-on-unmounted (lambda ()
                         (etaf-tanks--canvas-retire canvas)
                         (etaf-tanks--canvas-release canvas)
                         (setf (etaf-tanks--canvas-runtime canvas) nil)))
    (if graphic
        (progn
          ;; Resizing renders the box first; the strips follow once Godot
          ;; has drawn a frame for the new geometry.
          (etaf-watch geometry (lambda (next _old)
                                 (setf (etaf-tanks--canvas-geometry canvas) next
                                       (etaf-tanks--canvas-ascent canvas) (plist-get next :ascent))
                                 (etaf-tanks--canvas-adopt canvas)
                                 (etaf-tanks--canvas-present canvas))
                      :flush 'post :test #'equal)
          (etaf-watch frame (lambda (next _old)
                              (setf (etaf-tanks--canvas-frame canvas) next)
                              (when (etaf-tanks--canvas-adopt canvas)
                                (etaf-tanks--canvas-present canvas)))
                      :flush 'post :test #'equal))
      (etaf-watch text (lambda (next _old)
                         (let ((runtime (etaf-tanks--canvas-runtime canvas)))
                           (setcar (etaf-tanks--canvas-cell canvas) (or next " "))
                           (when (and runtime (etaf-runtime-mounted-p runtime))
                             (etaf-runtime-update-host-content runtime content-ref (or next " ")))))
                  :flush 'post :test #'equal)))
  :view
  (box :ref 'tanks-board :width (let ((g (etaf-value geometry)))
                                  (if (plist-get g :graphic)
                                      (list 'px (plist-get g :pixel-width))
                                    (list 'ch (plist-get g :columns))))
       :height (list 'lh (plist-get (etaf-value geometry) :rows))
       :position 'static :left '(px 0) :top '(lh 0) :z-index 0
       :wrap-mode 'none :overflow 'hidden :background-color background
       :tab-index 0 :role 'region :aria-label "战场"
    (text :ref content-ref :id content-id (expr (car (etaf-tanks--canvas-cell canvas))))))

(provide 'etaf-tanks-board)
;;; etaf-tanks-board.el ends here
