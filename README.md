# org-snitch
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

`org-snitch` is an Emacs package that brings powerful, context-aware `org-capture` templates natively integrated with `project.el`. It's inspired by the tsod snitch Go library, bringing project-linked notes, tasks, and bugs into a single centralized project file with beautiful local link rendering across your codebase.

With `org-snitch`, your `project.org` file travels with your project, keeping all context local. It also highlights links to your org records in comments or docstrings inside your source code, seamlessly bridging code and documentation.

## Features

- **Project-aware Captures:** Automatically targets the current project's tracking org file (default: `project.org`) based on Emacs' built-in `project.el`.
- **Dynamic Context:** Captures only activate when you are actively inside a project buffer, keeping your global target list clean.
- **Smart ID Generation:** Automatically generates deterministic `ID` tracking based on heading titles and numbers issues with a `TASK_NUM` property.
- **Auto-link Insertion:** Capturing over a region of code automatically replaces the region with a formatted org-id link back to the captured ticket/task.
- **Visual Overlays:** Turns raw org-links embedded in source comments (`[[id:hash][text]]`) into clean, stylized overlays (`[text]`) in any `prog-mode` buffer using `org-snitch-link-mode`.

## Installation

Using `use-package` and `straight.el` or `elpaca`:

```elisp
(use-package org-snitch
  :straight (org-snitch :type git :host github :repo "morazotti/org-snitch")
  :config
  ;; Initialize org-snitch capture templates and contexts
  (org-snitch-setup)
  ;; Enable the global minor mode for capture hooks
  (org-snitch-mode 1))
```

## Configuration

You can customize `org-snitch` behavior by setting the following variables **before** calling `(org-snitch-setup)`.

```elisp
(use-package org-snitch
  :straight t
  :custom
  ;; Change the default project file name
  (org-snitch-target-file "project.org")

  ;; Change the prefix key for all project templates (default is "p")
  (org-snitch-capture-key "p")

  ;; Define your project-specific capture sub-templates
  ;; Format: (KEY . DESCRIPTION) -> targets a heading of DESCRIPTION
  (org-snitch-capture-templates
   '(("t" . "Tasks")
     ("b" . "Bugs")
     ("f" . "Features")))

  :config
  (org-snitch-setup)
  (org-snitch-mode 1))
```

### Enabling Link Rendering in Code

To have your `id:` links rendered cleanly as `[Ticket Name]` overlays when navigating your source code files, enable `org-snitch-link-mode` in your preferred programming modes:

```elisp
(add-hook 'prog-mode-hook #'org-snitch-link-mode)
```

## Usage

1. Open any file in a project recognized by `project.el`.
2. Invoke `org-capture` (usually `C-c c`).
3. You will see a `[p] Project` option. Press `p`.
4. Select `t` for Tasks or `b` for Bugs.
5. Type your note and finalize the capture (`C-c C-c`).
6. The note is saved to `<project-root>/project.org` under the corresponding heading.

**Capturing from Code:**
If you select a region of code before invoking the capture, `org-snitch` will replace that region in the source buffer with a link back to the generated org heading upon finalizing the capture.

## License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.
