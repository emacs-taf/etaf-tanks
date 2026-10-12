;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-views.el --- A real-time battlefield with compact native controls
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-tanks-theme)
(require 'etaf-tanks-model)
(require 'etaf-tanks-arena)
(declare-function etaf-tanks-close "etaf-tanks" (&optional instance))
(defvar etaf-tanks-appearance)

(etaf-define-component etaf-tanks--theme-switch (&key appearance)
  :view
  (etaf-button :label (if (eq (etaf-value appearance) 'dark) "浅色" "暗色")
    :ref 'tanks-theme :variant 'ghost :help-echo "切换亮暗主题 · T"
    :on-press (lambda () (setf (etaf-value appearance)
                              (if (eq (etaf-value appearance) 'dark) 'light 'dark)))))

(etaf-define-component etaf-tanks--status (&key session)
  :bindings ((state (etaf-computed (lambda () (etaf-gamekit-view session :player)) :test #'equal)))
  :view
  (flex :width 'stretch :justify-content 'space-between :align-items 'center
    (etaf-progress :label "装甲" :width '(ch 22) :value (or (plist-get (etaf-value state) :health) 100)
      :variant (if (< (or (plist-get (etaf-value state) :health) 100) 40) 'danger 'success))
    (etaf-label :ref 'tanks-score :text (format "击毁 %d / 3" (or (plist-get (etaf-value state) :kills) 0)) :variant 'strong)
    (etaf-label :ref 'tanks-clock :text (let ((seconds (or (plist-get (etaf-value state) :seconds) 0)))
                                         (format "%02d:%02d" (/ seconds 60) (% seconds 60))) :variant 'muted)
    (etaf-label :ref 'tanks-cannon :text (if (eq t (plist-get (etaf-value state) :can_fire)) "主炮就绪" "主炮待命") :variant 'muted)))

(etaf-define-component etaf-tanks--controls (&key session)
  :bindings ((state (etaf-computed (lambda () (etaf-gamekit-view session :player)) :test #'equal)))
  :view
  (column :width 'stretch :item-gap '(lh 0)
    :region '(:id tanks-controls :label "驾驶与瞄准" :key "c" :enter tanks-fire)
    (flex :width 'stretch :justify-content 'space-between :align-items 'center
      (row :item-gap '(ch 1)
        (etaf-label :text "驾驶" :variant 'muted)
        (etaf-button :for (entry '(("n" "↑ 北" 0 -1) ("w" "← 西" -1 0) ("s" "↓ 南" 0 1) ("e" "→ 东" 1 0)))
          :key (car entry) :ref (intern (concat "tanks-drive-" (car entry))) :label (cadr entry) :variant 'secondary
          :disabled (or (eq t (plist-get (etaf-value state) :paused)) (etaf-tanks--ended-p (etaf-value state)))
          :on-press (lambda () (etaf-tanks--move session (nth 2 entry) (nth 3 entry)))))
      (etaf-button :label "开火 · F" :ref 'tanks-fire
        :disabled (not (eq t (plist-get (etaf-value state) :can_fire)))
        :on-press (lambda () (etaf-tanks--fire session))))
    (flex :width 'stretch :justify-content 'space-between :align-items 'center
      (row :item-gap '(ch 1)
        (etaf-label :text "瞄准" :variant 'muted)
        (etaf-button :for (entry '(("n" "北") ("w" "西") ("s" "南") ("e" "东")))
          :key (car entry) :ref (intern (concat "tanks-aim-" (car entry))) :label (cadr entry)
          :variant (if (equal (car entry) (plist-get (etaf-value state) :facing)) 'secondary 'ghost)
          :disabled (etaf-tanks--ended-p (etaf-value state))
          :on-press (lambda () (etaf-tanks--send session "aim" (list :direction (car entry))))))
      (etaf-button :label "停车" :ref 'tanks-stop :variant 'ghost
        :disabled (or (etaf-tanks--ended-p (etaf-value state)) (not (eq t (plist-get (etaf-value state) :moving))))
        :on-press (lambda () (etaf-tanks--send session "stop"))))))

(etaf-define-component etaf-tanks--log (&key session)
  :bindings ((events (etaf-computed (lambda () (etaf-gamekit-view session :events)) :test #'equal)))
  :view
  (row :width 'stretch :item-gap '(ch 1)
    (etaf-tag :text (or (plist-get (car (etaf-value events)) :title) "待命")
      :variant (intern (or (plist-get (car (etaf-value events)) :kind) "info")))
    (etaf-label :text (or (plist-get (car (etaf-value events)) :detail) "") :variant 'muted :wrap-mode 'word)))

(etaf-define-component etaf-tanks--app (&key session)
  :bindings ((appearance (etaf-ref (if (eq etaf-tanks-appearance 'auto)
                                      (if (eq (frame-parameter nil 'background-mode) 'dark) 'dark 'light)
                                    etaf-tanks-appearance)))
             (theme (etaf-computed (lambda () (if (eq (etaf-value appearance) 'dark)
                                                 etaf-tanks--dark-theme etaf-tanks--light-theme)) :test #'equal))
             (state (etaf-computed (lambda () (etaf-gamekit-view session :player)) :test #'equal))
             (metrics (etaf-tanks--metrics)) (help (etaf-ref nil))
             (viewport (etaf-computed (lambda () (etaf-viewport)) :test #'equal))
             (compact (etaf-computed (lambda () (< (or (cdr (etaf-value viewport)) 44) 38)))))
  :setup
  (progn
    (etaf-theme-provide theme)
    (etaf-watch viewport
      (lambda (_size _old)
        (when-let* ((buffer (etaf-gamekit-buffer session))
                    (runtime (etaf-runtime-for-buffer buffer))
                    (bounds (etaf-host-ref-size runtime 'tanks-root)))
          (dolist (window (get-buffer-window-list buffer nil t))
            (when (>= (window-body-width window t) (car bounds)) (set-window-hscroll window 0))
            (when (>= (window-body-height window) (cdr bounds))
              (set-window-start window (with-current-buffer buffer (point-min)) t)))))
      :flush 'post))
  :view
  (column :width '(vw 100) :height '(vh 100)
    :cross-align (if (< (or (car (etaf-value viewport)) 0)
                       (* (frame-char-width) (+ 4 (plist-get metrics :columns)))) 'start 'center)
    :background-color (etaf-tanks--color :ui-bg) :color (etaf-tanks--color :ui-fg)
    :on-direction (lambda (direction)
                    (pcase direction
                      ('up (etaf-tanks--move session 0 -1)) ('down (etaf-tanks--move session 0 1))
                      ('left (etaf-tanks--move session -1 0)) ('right (etaf-tanks--move session 1 0)))
                    'handled)
    :keys (list
           (list "S-<up>" (lambda () (etaf-tanks--send session "aim" '(:direction "n"))) "原地瞄北")
           (list "S-<left>" (lambda () (etaf-tanks--send session "aim" '(:direction "w"))) "原地瞄西")
           (list "S-<down>" (lambda () (etaf-tanks--send session "aim" '(:direction "s"))) "原地瞄南")
           (list "S-<right>" (lambda () (etaf-tanks--send session "aim" '(:direction "e"))) "原地瞄东")
           (list "f" (lambda () (etaf-tanks--fire session)) "开火")
           (list "x" (lambda () (etaf-tanks--send session "stop")) "停车")
           (list "p" (lambda () (etaf-tanks--toggle-pause session)) "开始或暂停")
           (list "n" (lambda () (etaf-tanks--send session "restart")) "重新出击")
           (list "C-s" (lambda () (etaf-tanks--snapshot session "save")) "保存战斗")
           (list "C-o" (lambda () (etaf-tanks--snapshot session "load")) "读取战斗")
           (list "t" (lambda () (setf (etaf-value appearance) (if (eq (etaf-value appearance) 'dark) 'light 'dark))) "亮暗主题")
           (list "<f1>" (lambda () (etaf-tanks--pause-for-input session) (setf (etaf-value help) t)) "暂停并打开说明")
           (list "q" (lambda () (etaf-tanks-close session)) "退出"))
    (column :ref 'tanks-root :width (list 'ch (+ 4 (plist-get metrics :columns)))
      :padding (if (etaf-value compact) '((lh 0) (ch 2)) '((lh 1) (ch 2)))
      :item-gap (if (etaf-value compact) '(lh 0) '(lh 1))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text "钢铁洪流 · 坦克战" :variant 'strong)
        (row :item-gap '(ch 1)
          (etaf-button :label (if (eq t (plist-get (etaf-value state) :paused))
                                 (if (zerop (or (plist-get (etaf-value state) :seconds) 0)) "开始 · P" "继续 · P")
                               "暂停 · P")
            :ref 'tanks-pause :disabled (or (null (etaf-value state)) (etaf-tanks--ended-p (etaf-value state)))
            :on-press (lambda () (etaf-tanks--toggle-pause session)))
          (etaf-button :label "重开" :ref 'tanks-new :variant 'ghost :on-press (lambda () (etaf-tanks--send session "restart")))
          (etaf-button :label "保存" :ref 'tanks-save :variant 'ghost :on-press (lambda () (etaf-tanks--snapshot session "save")))
          (etaf-button :label "读取" :ref 'tanks-load :variant 'ghost :on-press (lambda () (etaf-tanks--snapshot session "load")))
          (etaf-tanks--theme-switch :appearance appearance)
          (etaf-button :label "说明" :ref 'tanks-help :variant 'ghost
            :on-press (lambda () (etaf-tanks--pause-for-input session) (setf (etaf-value help) t)))))
      (etaf-label :if (null (etaf-value state)) :text "正在开赴战场…" :variant 'muted)
      (etaf-tanks--status :if (etaf-value state) :session session)
      (etaf-tanks--arena :if (etaf-value state) :session session :palette theme :metrics metrics)
      (etaf-tanks--controls :if (etaf-value state) :session session)
      (etaf-alert :if (etaf-tanks--ended-p (etaf-value state))
        :title (if (eq t (plist-get (etaf-value state) :won)) "战区肃清" "战车损毁")
        :message "按 N 或「重开」重新出击。" :variant (if (eq t (plist-get (etaf-value state) :won)) 'success 'danger))
      (etaf-tanks--log :if (not (etaf-tanks--ended-p (etaf-value state))) :session session)
      (etaf-alert :if (etaf-gamekit-last-error session) :title "操作未生效" :message (etaf-gamekit-last-error session) :variant 'danger)
      (etaf-dialog :open help :title "驾驶与战斗" :width '(ch 64) :compact t
        :on-close (lambda () (setf (etaf-value help) nil))
        (column :item-gap '(lh 1)
          (etaf-label :text "这是一场实时战斗：开始后敌车会自主追击和开火，炮弹持续飞行。击毁三辆敌车即获胜，装甲归零则失败。" :wrap-mode 'word)
          (etaf-label :text "方向键向四个方向驾驶；每次按键行驶一格，按住可以连续驾驶。Shift+方向键原地瞄准，F 开火，X 停车。也可点击下方驾驶和瞄准按钮。" :wrap-mode 'word)
          (etaf-label :text "利用掩体阻挡炮弹，看到敌车时转向开火。带圆标的绿色战车是我方，叉形标记是敌车，亮黄色是炮弹。" :wrap-mode 'word)
          (etaf-label :text "P 暂停；打开说明或存档提示也会先暂停。关闭说明后按 P 继续。读取存档后保持暂停，清空移动路线和在途炮弹。" :wrap-mode 'word)
          (etaf-label :text "T 切换亮暗主题，N 重开，Q 退出。主题和窗口变化不重启 Godot。" :wrap-mode 'word))))))

(defun etaf-tanks--view (session)
  "Compose the native battlefield from public ETAF and GameKit APIs."
  (etaf-view (etaf-tanks--app :session session)))
(provide 'etaf-tanks-views)
;;; etaf-tanks-views.el ends here
