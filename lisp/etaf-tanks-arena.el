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
         (shadow (plist-get palette :tank-shadow)) parts)
    (push (format "<rect width='672' height='416' rx='6' fill='%s'/>" floor) parts)
    (push (format "<g fill='none' stroke='%s' stroke-width='.6' opacity='.50'>" grid) parts)
    (dotimes (r 14)
      (when (<= (- top-y 1) (* r 32) (+ bottom 1))
        (push (format "<path d='M%.2f %d H%.2f'/>" left (* r 32) right) parts)))
    (dotimes (c 22)
      (when (<= (- left 1) (* c 32) (+ right 1))
        (push (format "<path d='M%d %.2f V%.2f'/>" (* c 32) top-y bottom) parts)))
    (push "</g>" parts)
    (cl-loop for line in terrain for row from 0
             when (and (< (* row 32) bottom) (> (* (1+ row) 32) top-y)) do
             (dotimes (column 21)
               (when (and (= (aref line column) ?#)
                          (< (* column 32) right) (> (* (1+ column) 32) left))
                 (push (format "<g transform='translate(%d,%d)'><rect x='1' y='2' width='30' height='30' rx='3' fill='%s'/><rect x='1' y='1' width='30' height='27' rx='3' fill='%s'/><path d='M5 5 H27 M5 5 V24' fill='none' stroke='%s' stroke-width='1' opacity='.75'/><path d='M4 16 H28' fill='none' stroke='%s' stroke-width='.7' opacity='.4'/></g>"
                               (* column 32) (* row 32) shadow wall top shadow) parts))))
    (apply #'concat (nreverse parts))))

(defun etaf-tanks--tank-art (entity palette)
  "Draw the hull, treads and barrel of native ENTITY in PALETTE."
  (let* ((friendly (equal (plist-get entity :kind) "player"))
         (body (plist-get palette (if friendly :tank-player :tank-enemy)))
         (top (plist-get palette (if friendly :tank-player-top :tank-enemy-top)))
         (track (plist-get palette :tank-track))
         (rotation (pcase (plist-get entity :facing) ("n" 0) ("e" 90) ("s" 180) (_ 270))))
    (format
     (concat "<g transform='translate(%.2f,%.2f) rotate(%d)'>"
             "<rect x='-11' y='-10' width='22' height='24' rx='4' fill='%s' opacity='.5'/>"
             "<rect x='-11' y='-12' width='6' height='24' rx='2.5' fill='%s'/>"
             "<rect x='5' y='-12' width='6' height='24' rx='2.5' fill='%s'/>"
             "<path d='M-10 -8 h4 M-10 -3 h4 M-10 2 h4 M-10 7 h4 M6 -8 h4 M6 -3 h4 M6 2 h4 M6 7 h4' stroke='%s' stroke-width='1.4' opacity='.65'/>"
             "<rect x='-7' y='-10' width='14' height='20' rx='3' fill='%s'/>"
             "<path d='M-4 7 H4 M-4 4 H4' stroke='%s' stroke-width='1' opacity='.5'/>"
             "<rect x='-2' y='-18' width='4' height='18' rx='1' fill='%s'/>"
             "<circle r='6' fill='%s'/><circle cy='-1' r='4.4' fill='%s'/>%s</g>")
     (* 32 (plist-get entity :px)) (* 32 (plist-get entity :py)) rotation
     (plist-get palette :tank-shadow) track track top body track body body top
     (if friendly
         (format "<circle cy='-1' r='1.4' fill='%s'/>" (plist-get palette :tank-ink))
       (format "<path d='M-2 -3 L2 1 M2 -3 L-2 1' stroke='%s' stroke-width='1'/>" track)))))

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
            (push (format "<circle cx='%.2f' cy='%.2f' r='3.2' fill='%s' stroke='%s' stroke-width='1'/>"
                          (* 32 (plist-get shell :px)) (* 32 (plist-get shell :py))
                          (plist-get palette :tank-shell) (plist-get palette :tank-shadow)) parts))
          (dolist (effect effects)
            (push (format "<g transform='translate(%.2f,%.2f)' stroke='%s' stroke-width='2'><path d='M-7 0 H7 M0 -7 V7 M-5 -5 L5 5 M-5 5 L5 -5'/><circle r='4' fill='%s' stroke='none'/></g>"
                          (* 32 (plist-get effect :px)) (* 32 (plist-get effect :py))
                          (plist-get palette :tank-spark) (plist-get palette :tank-shell)) parts))
          (let ((source (list 'image :type 'svg :data
                              (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='%.6f %.6f %.6f %.6f' preserveAspectRatio='none'>%s</svg>"
                                      (* (cadr span) (/ (plist-get metrics :pixel-width) (plist-get metrics :columns)))
                                      (plist-get metrics :line-height)
                                      (nth 0 region) (nth 1 region) (nth 2 region) (nth 3 region)
                                      (apply #'concat (nreverse parts))))))
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
    :tab-index 0 :role 'region :aria-label "战场：WASD 驾驶，空格开火"
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
