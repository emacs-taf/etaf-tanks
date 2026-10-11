;;; -*- lexical-binding: t; -*-
;;; etaf-tanks-theme.el --- Field-map and night-operation palettes
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf)
(defconst etaf-tanks--light-theme
  '(:ui-bg "#F4F5F1" :ui-fg "#293A3A" :ui-muted-fg "#7B8982"
    :ui-panel-bg "#FFFFFF" :ui-panel-fg "#293A3A" :ui-panel-border "#DCE3D9"
    :ui-border "#DCE3D9" :ui-accent "#347C68" :ui-accent-fg "#FFFFFF"
    :ui-button-primary-bg "#347C68" :ui-button-primary-fg "#FFFFFF"
    :ui-button-secondary-bg "#DEEAE2" :ui-button-secondary-fg "#365D50"
    :ui-button-ghost-fg "#546D61" :ui-disabled-bg "#E8ECE5" :ui-disabled-fg "#9EAEA2"
    :ui-disabled-border "#DCE3D9" :ui-divider-bg "#DCE3D9"
    :ui-info-bg "#E2ECE8" :ui-info-fg "#3D6E60" :ui-info-border "#CADCD4"
    :ui-success-bg "#E3EFE5" :ui-success-fg "#37794C" :ui-success-border "#C7DFCB"
    :ui-warning-bg "#F6EBD0" :ui-warning-fg "#8B6D2B" :ui-warning-border "#E7D7AF"
    :ui-danger-bg "#F6E4DF" :ui-danger-fg "#A85246" :ui-danger-border "#E4C7C0"
    :ui-progress-track "#DCE5D9"
    :tank-floor "#DCE6D4" :tank-grid "#B3C4A9" :tank-wall "#8B9985"
    :tank-wall-top "#B8C3AB" :tank-shadow "#5D715E" :tank-track "#314B42"
    :tank-player "#398E74" :tank-player-top "#8AD3B1" :tank-enemy "#BF6B57"
    :tank-enemy-top "#F0B79E" :tank-shell "#FFC45B" :tank-spark "#D98238"
    :tank-ink "#F8FFF4")
  "Daylight tactical map with sage terrain and clear armour silhouettes.")

(defconst etaf-tanks--dark-theme
  '(:ui-bg "#171F27" :ui-fg "#E0E9E8" :ui-muted-fg "#8B9DA4"
    :ui-panel-bg "#22303A" :ui-panel-fg "#E0E9E8" :ui-panel-border "#35474F"
    :ui-border "#35474F" :ui-accent "#81CDB6" :ui-accent-fg "#17382C"
    :ui-button-primary-bg "#81CDB6" :ui-button-primary-fg "#17382C"
    :ui-button-secondary-bg "#324C4B" :ui-button-secondary-fg "#BDDED3"
    :ui-button-ghost-fg "#B1C5C8" :ui-disabled-bg "#22303A" :ui-disabled-fg "#607880"
    :ui-disabled-border "#35474F" :ui-divider-bg "#35474F"
    :ui-info-bg "#29434B" :ui-info-fg "#A9CED4" :ui-info-border "#3E5E66"
    :ui-success-bg "#294335" :ui-success-fg "#AED7B8" :ui-success-border "#42664E"
    :ui-warning-bg "#423A2D" :ui-warning-fg "#E4CB8E" :ui-warning-border "#655639"
    :ui-danger-bg "#47343A" :ui-danger-fg "#EDB0A6" :ui-danger-border "#715049"
    :ui-progress-track "#35474F"
    :tank-floor "#263A40" :tank-grid "#425D62" :tank-wall "#50666C"
    :tank-wall-top "#7F979B" :tank-shadow "#142B30" :tank-track "#16262C"
    :tank-player "#7DCEB4" :tank-player-top "#D5F3E1" :tank-enemy "#D78369"
    :tank-enemy-top "#F3C6AC" :tank-shell "#FFDF88" :tank-spark "#F1AD65"
    :tank-ink "#F4FFF8")
  "Night-operation palette with distinct friendly and hostile silhouettes.")

(defun etaf-tanks--color (token)
  "Read reactive TOKEN from this instance's scoped theme."
  (etaf-theme-token token (plist-get etaf-tanks--light-theme token)))
(provide 'etaf-tanks-theme)
;;; etaf-tanks-theme.el ends here
