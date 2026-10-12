;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-arena.el --- Retained local artwork for the native battlefield
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-tanks-model)

(defun etaf-tanks--metrics ()
  "Choose fixed battlefield metrics for the opening font."
  (if (and (display-graphic-p) (image-type-available-p 'svg))
      (let ((columns (* 2 (round (/ (* 20.0 (frame-char-height) 21)
                                     (* 26 (frame-char-width)))))))
        (list :rows 20 :columns columns :graphic t
              :pixel-width (* columns (frame-char-width)) :line-height (frame-char-height)))
    '(:rows 13 :columns 42 :graphic nil)))

(defun etaf-tanks--terrain-art (terrain palette region)
  "Draw only the static TERRAIN intersecting REGION, in native world units."
  (let* ((left (nth 0 region)) (top-y (nth 1 region))
         (right (+ left (nth 2 region))) (bottom (+ top-y (nth 3 region)))
         (floor (plist-get palette :tank-floor)) (grid (plist-get palette :tank-grid))
         (wall (plist-get palette :tank-wall)) (top (plist-get palette :tank-wall-top))
         (shadow (plist-get palette :tank-shadow)) (lattice nil) parts)
    (push (etaf-ui-svg-rect 0 0 672 416 :rx 6 :fill floor) parts)
    (dotimes (r 14)
      (when (<= (- top-y 1) (* r 32) (+ bottom 1))
        (push (etaf-ui-svg-line left (* r 32) right (* r 32)) lattice)))
    (dotimes (c 22)
      (when (<= (- left 1) (* c 32) (+ right 1))
        (push (etaf-ui-svg-line (* c 32) top-y (* c 32) bottom) lattice)))
    (push (etaf-ui-svg-group (apply #'concat (nreverse lattice))
                             :fill "none" :stroke grid :stroke-width .6 :opacity .50)
          parts)
    (cl-loop for line in terrain for row from 0
             when (and (< (* row 32) bottom) (> (* (1+ row) 32) top-y)) do
             (dotimes (column 21)
               (when (and (= (aref line column) ?#)
                          (< (* column 32) right) (> (* (1+ column) 32) left))
                 (push (etaf-ui-svg-group
                        (concat
                         (etaf-ui-svg-rect 1 2 30 30 :rx 3 :fill shadow)
                         (etaf-ui-svg-rect 1 1 30 27 :rx 3 :fill wall)
                         (etaf-ui-svg-line 5 5 27 5 :stroke top
                                           :stroke-width 1 :opacity .75)
                         (etaf-ui-svg-line 5 5 5 24 :stroke top
                                           :stroke-width 1 :opacity .75)
                         (etaf-ui-svg-line 4 16 28 16 :stroke shadow
                                           :stroke-width .7 :opacity .4))
                        :transform (format "translate(%d,%d)"
                                           (* column 32) (* row 32)))
                       parts))))
    (apply #'concat (nreverse parts))))

(defun etaf-tanks--tank-art (entity palette)
  "Draw the hull, treads and barrel of native ENTITY in PALETTE."
  (let* ((friendly (equal (plist-get entity :kind) "player"))
         (body (plist-get palette (if friendly :tank-player :tank-enemy)))
         (top (plist-get palette (if friendly :tank-player-top :tank-enemy-top)))
         (track (plist-get palette :tank-track))
         (rotation (pcase (plist-get entity :facing) ("n" 0) ("e" 90) ("s" 180) (_ 270))))
    (etaf-ui-svg-group
     (concat
      (etaf-ui-svg-rect -11 -10 22 24 :rx 4
                        :fill (plist-get palette :tank-shadow) :opacity .5)
      (etaf-ui-svg-rect -11 -12 6 24 :rx 2.5 :fill track)
      (etaf-ui-svg-rect 5 -12 6 24 :rx 2.5 :fill track)
      (etaf-ui-svg-path
       "M-10 -8 h4 M-10 -3 h4 M-10 2 h4 M-10 7 h4 M6 -8 h4 M6 -3 h4 M6 2 h4 M6 7 h4"
       :stroke track :stroke-width 1.4 :opacity .65)
      (etaf-ui-svg-rect -7 -10 14 20 :rx 3 :fill top)
      (etaf-ui-svg-path "M-4 7 H4 M-4 4 H4" :stroke body :stroke-width 1 :opacity .5)
      (etaf-ui-svg-rect -2 -18 4 18 :rx 1 :fill body)
      (etaf-ui-svg-circle 0 0 6 :fill body)
      (etaf-ui-svg-circle 0 -1 4.4 :fill top)
      (if friendly
          (etaf-ui-svg-circle 0 -1 1.4 :fill (plist-get palette :tank-ink))
        (etaf-ui-svg-path "M-2 -3 L2 1 M2 -3 L-2 1" :stroke track :stroke-width 1)))
     :transform (format "translate(%.2f,%.2f) rotate(%d)"
                        (* 32 (plist-get entity :px)) (* 32 (plist-get entity :py))
                        rotation))))

(defun etaf-tanks--visible-in (item radius region)
  "Whether ITEM artwork with RADIUS intersects display REGION.
This is presentation culling, never collision or native-world simulation."
  (let ((x (* 32 (plist-get item :px))) (y (* 32 (plist-get item :py))))
    (and (<= (- (nth 0 region) radius) x (+ (nth 0 region) (nth 2 region) radius))
         (<= (- (nth 1 region) radius) y (+ (nth 1 region) (nth 3 region) radius)))))

(defun etaf-tanks--arena-patch (terrain-cache frame-cache world palette metrics row span)
  "Return a local display region in character SPAN, containing nearby sprites."
  (let* ((scale (/ 672.0 (plist-get metrics :columns)))
         (region (list (* (car span) scale) (* row (/ 416.0 20)) (* (cadr span) scale) (/ 416.0 20)))
         (entities (cl-loop for item in (plist-get world :entities)
                            when (etaf-tanks--visible-in item 20 region) collect item))
         (shells (cl-loop for item in (plist-get world :shells)
                          when (etaf-tanks--visible-in item 4 region) collect item))
         (effects (cl-loop for item in (plist-get world :effects)
                           when (etaf-tanks--visible-in item 9 region) collect item))
         (base-key (list palette region (plist-get world :terrain)))
         (key (list base-key entities shells effects)))
    (or (gethash key frame-cache)
        (let* ((base (or (gethash base-key terrain-cache)
                         (puthash base-key (etaf-tanks--terrain-art (plist-get world :terrain) palette region) terrain-cache)))
               (parts (list base)))
          (dolist (entity entities) (push (etaf-tanks--tank-art entity palette) parts))
          (dolist (shell shells)
            (push (etaf-ui-svg-circle
                   (* 32 (plist-get shell :px)) (* 32 (plist-get shell :py)) 3.2
                   :fill (plist-get palette :tank-shell)
                   :stroke (plist-get palette :tank-shadow) :stroke-width 1)
                  parts))
          (dolist (effect effects)
            (push (etaf-ui-svg-group
                   (concat
                    (etaf-ui-svg-path "M-7 0 H7 M0 -7 V7 M-5 -5 L5 5 M-5 5 L5 -5")
                    (etaf-ui-svg-circle 0 0 4 :fill (plist-get palette :tank-shell)
                                        :stroke "none"))
                   :transform (format "translate(%.2f,%.2f)"
                                      (* 32 (plist-get effect :px))
                                      (* 32 (plist-get effect :py)))
                   :stroke (plist-get palette :tank-spark) :stroke-width 2)
                  parts))
          (let ((source
                 (etaf-ui-svg-image
                  (apply #'concat (nreverse parts))
                  (* (cadr span) (/ (plist-get metrics :pixel-width)
                                   (plist-get metrics :columns)))
                  (plist-get metrics :line-height)
                  region 'none)))
            (when (> (hash-table-count frame-cache) 512) (clrhash frame-cache))
            (puthash key source frame-cache))))))

(etaf-define-component etaf-tanks--arena (&key session palette metrics)
  :bindings ((world (etaf-computed (lambda () (etaf-gamekit-view session :world)) :test #'equal))
             (spans (cl-loop for column below 4
                             for start = (/ (* column (plist-get metrics :columns)) 4)
                             collect (list start (- (/ (* (1+ column) (plist-get metrics :columns)) 4) start))))
             (terrain-cache (make-hash-table :test #'equal))
             (frame-cache (make-hash-table :test #'equal)))
  :view
  (box :ref 'tanks-board :width (list 'ch (plist-get metrics :columns))
    :height (list 'lh (plist-get metrics :rows)) :overflow 'hidden
    :tab-index 0 :role 'region :aria-label "战场：方向键驾驶，F 开火"
    :region '(:id tanks-field :label "战场" :key "b" :enter tanks-board)
    (row :if (plist-get metrics :graphic) :ref 'tanks-canvas
      (column :for (span spans) :key (car span)
        (image :for (line (number-sequence 0 19)) :key line
          :columns (cadr span) :rows 1
          :src (etaf-tanks--arena-patch terrain-cache frame-cache
                                      (etaf-value world) (etaf-value palette) metrics line span))))
    (etaf-tile-grid :if (not (plist-get metrics :graphic)) :rows 13 :columns 21 :cell-width 2
      :cell-text (lambda (r c) (cadr (etaf-tanks--cell (etaf-value world) r c)))
      :cell-color (lambda (r c)
                    (plist-get (etaf-value palette)
                               (pcase (car (etaf-tanks--cell (etaf-value world) r c))
                                 (:player :tank-player) (:enemy :tank-enemy) (:shell :tank-shell)
                                 (:wall :tank-wall-top) (_ :tank-grid))))
      :cell-background (lambda (_r _c) (plist-get (etaf-value palette) :tank-floor)))))

(provide 'etaf-tanks-arena)
;;; etaf-tanks-arena.el ends here
