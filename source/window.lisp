;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(in-package :nyxt)

(hooks:define-hook-type window-buffer (function (window buffer)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export 'window)
  (export
   '(id
     message-buffer-height
     message-buffer-style
     minibuffer-open-height
     minibuffer-open-single-line-height
     input-dispatcher
     window-set-active-buffer-hook
     status-formatter
     window-delete-hook)))
(defclass window ()
  ((id :accessor id
       :initarg :id
       :type string
       :initform "")
   (active-buffer :reader active-buffer :initform nil)
   (active-minibuffers :accessor active-minibuffers :initform nil
                       :documentation "The stack of currently active minibuffers.")
   ;; TODO: each frame should have a status buffer, not each window
   (status-buffer :accessor status-buffer :initform nil)
   (message-buffer-height :accessor message-buffer-height :initform 16
                          :type integer
                          :documentation "The height of the message buffer in pixels.")
   (message-buffer-style :accessor message-buffer-style :initform
                         (cl-css:css
                          '((body
                             :font-size "12px"
                             :padding 0
                             :padding-left "4px"
                             :margin 0))))
   (minibuffer-open-height :accessor minibuffer-open-height :initform 256
                           :type integer
                           :documentation "The height of the minibuffer when open.")
   (minibuffer-open-single-line-height :accessor minibuffer-open-single-line-height
                                       :initform 35
                                       :type integer
                                       :documentation "The height of
 the minibuffer when open for a single line of input.")
   (input-dispatcher :accessor input-dispatcher
                     :initform #'dispatch-input-event
                     :type function
                     :documentation "Function to process input events.
It takes EVENT, BUFFER, WINDOW and PRINTABLE-P parameters.
Cannot be null.")
   (window-set-active-buffer-hook :accessor window-set-active-buffer-hook
                                  :initform (make-hook-window-buffer)
                                  :type hook-window-buffer
                                  :documentation "Hook run before `window-set-active-buffer' takes effect.
The handlers take the window and the buffer as argument.")
   (status-formatter :accessor status-formatter
                     :initform #'format-status
                     :type (function (window) string)
                     :documentation "Function of a window argument that returns
a string to be printed in the status view.
Cannot be null.

Example formatter that prints the buffer indices over the total number of buffers:

\(defun my-format-status (window)
  (let* ((buffer (current-buffer window))
         (buffer-count (1+ (or (position buffer
                                         (sort (buffer-list)
                                               #'string<
                                               :key #'id))
                               0))))
    (str:concat
     (markup:markup
      (:b (format nil \"[~{~a~^ ~}]\"
                  (mapcar (lambda (m) (str:replace-all \"-mode\" \"\"
                                                       (str:downcase
                                                        (class-name (class-of m)))))
                          (modes buffer)))))
     (format nil \" (~a/~a) \"
             buffer-count
             (length (buffer-list)))
     (format nil \"~a~a — ~a\"
            (if (eq (slot-value buffer 'load-status) :loading)
                \"(Loading) \"
                \"\")
            (object-display (url buffer))
            (title buffer)))))")
   (window-delete-hook :accessor window-delete-hook
                       :initform (make-hook-window)
                       :type hook-window
                       :documentation "Hook run after `ffi-window-delete' takes effect.
The handlers take the window as argument.")))

(defmethod (setf active-buffer) (buffer (window window))
  (setf (slot-value window 'active-buffer) buffer)
  (print-status))

(defun print-status (&optional status window)
  (let ((window (or window (current-window))))
    (when (status-buffer window)
      (ffi-print-status
       window
       (or status
           (funcall-safely (status-formatter window) window))))))

(hooks:define-hook-type window (function (window)))

(defmethod object-string ((window window))
  (match (active-buffer window)
    ((guard b b)
     (object-string b))
    (_ (format nil "<#WINDOW ~a>" (id window)))))

(defun window-suggestion-filter ()
  (let ((windows (window-list)))
    (lambda (minibuffer)
      (fuzzy-match (input-buffer minibuffer) windows))))

(declaim (ftype (function (browser)) window-make))
(export-always 'window-make)
(defun window-make (browser)
  (let* ((window (ffi-window-make browser)))
    (setf (gethash (id window) (windows browser)) window)
    (unless (slot-value browser 'last-active-window)
      (setf (slot-value browser 'last-active-window) window))
    (hooks:run-hook (window-make-hook browser) window)
    window))

(declaim (ftype (function (window)) window-delete))
(defun window-delete (window)
  "This function must be called by the renderer when a window is deleted."
  (ffi-window-delete window)
  (hooks:run-hook (window-delete-hook window) window)
  (remhash (id window) (windows *browser*))
  (when (zerop (hash-table-count (windows *browser*)))
    (quit)))

(define-command delete-window ()
  "Delete the queried window(s)."
  (with-result (windows (read-from-minibuffer
                         (make-minibuffer
                          :input-prompt "Delete window(s)"
                          :multi-selection-p t
                          :suggestion-function (window-suggestion-filter))))
    (mapcar #'delete-current-window windows)))

(define-command delete-current-window (&optional (window (current-window)))
  "Delete WINDOW, or the currently active window if unspecified."
  (let ((window-count (hash-table-count (windows *browser*))))
    (cond ((and window (> window-count 1))
           (ffi-window-delete window))
          (window
           (echo "Can't delete sole window.")))))

(define-command make-window (&optional buffer)
  "Create a new window."
  (let ((window (window-make *browser*))
        (buffer (or buffer (make-buffer :url :default))))
    (window-set-active-buffer window buffer)
    (values window buffer)))

(define-command fullscreen-current-window (&optional (window (current-window)))
  "Fullscreen WINDOW, or the currently active window if unspecified."
  (ffi-window-fullscreen window))

(define-command unfullscreen-current-window (&optional (window (current-window)))
  "Unfullscreen WINDOW, or the currently active window if unspecified."
  (ffi-window-unfullscreen window))
