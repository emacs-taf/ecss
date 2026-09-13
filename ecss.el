;;; ecss.el --- Pure extensible CSS cascade engine -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Geekinney

;; Author: Geekinney <kinneyzhang666@gmail.com>
;; URL: https://github.com/geekinney/ecss
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: lisp, extensions
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Assisted-by: Codex

;;; Commentary:

;; ECSS is a pure, consumer-independent selector and CSS cascade engine.
;; Consumers register their own property vocabulary, expose their own subject
;; values through adapters, and decide what computed values mean.  ECSS never
;; mutates buffers and has no dependency on TP, Ebox, or the historical ECSS
;; repository.

;;; Code:

(require 'ecss-selector)
(require 'ecss-cascade)
(require 'ecss-file)

(provide 'ecss)
;;; ecss.el ends here
