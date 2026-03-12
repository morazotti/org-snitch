# org-snitch
[![CI](https://github.com/morazotti/org-snitch/actions/workflows/test.yml/badge.svg)](https://github.com/morazotti/org-snitch/actions/workflows/test.yml) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

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

  ;; Treat submodules as independent projects (default is t)
  (org-snitch-independent-submodules t)

  ;; Define your project-specific capture sub-templates
  ;; Format: (KEY . DESCRIPTION) -> targets a heading of DESCRIPTION
  (org-snitch-capture-templates
   '(("t" . "Tasks")
     ("b" . "Bugs")
     ("f" . "Features")))

  :bind
  (("C-c s" . org-snitch-dispatch)
   :map org-snitch-link-mode-map
   ("C-c C-o" . org-open-at-point-global)
   ("C-c C-d" . org-snitch-mark-done))

  :config
  (org-snitch-setup)
  (org-snitch-mode 1))
```

> **Note:** Enabling `org-snitch-mode` automatically turns on `org-snitch-link-mode` for all your programming modes (`prog-mode`), ensuring that task IDs found in your source code comments are seamlessly rendered as clean `[Task Title]` overlays.

## Usage

### Interactive Dashboard (Transient)

`org-snitch` includes a built-in Transient menu that acts as a unified dashboard for all your project tasks. Inside any project file, you can call:

```elisp
M-x org-snitch-dispatch
```

This will open an interactive menu displaying:
- The name of your current project
- The total count of open (`TODO`) and finished (`DONE`) tasks
- Quick bindings to Capture a new task, Insert a link, Find references, Mark a task as Done, or Open the project tracking file.

### Basic Workflow

1. Open any file in a project recognized by `project.el`.
2. Invoke `org-capture` (usually `C-c c`).
3. You will see a `[p] Project` option. Press `p`.
4. Select `t` for Tasks or `b` for Bugs.
5. Type your note and finalize the capture (`C-c C-c`).
6. The note is saved to `<project-root>/project.org` under the corresponding heading.

**Capturing from Code:**
If you select a region of code before invoking the capture, `org-snitch` will replace that region in the source buffer with a link back to the generated org heading upon finalizing the capture.
Additionally, the newly generated task in your `project.org` file will automatically receive a `:SOURCE:` property containing an `org-mode` link to the exact line in the code file that triggered the capture. This allows for rich bidirectional tracking.

### Inserting Existing Task Links

You can insert a link to an existing task anywhere in your code interactively by calling:

```elisp
M-x org-snitch-insert-link
```

This presents a `completing-read` interface with all tasks in your `project.org` file. Selecting a task inserts a formatted link (e.g., `// TASKS: (#123) [[id:hash][Refactor loop]]`) at point, automatically wrapped in the current mode's comment syntax.

When `org-snitch-link-mode` is enabled, an overlay will make these links look clean in your source code. You can interact with these links directly:
- **`C-c C-o`**: Open the task in `project.org`.
- **`C-c C-d`**: Instantly mark the task as `DONE` in the background without leaving your source file.

### Tracking Task References

To find all locations in your project where a specific task is referenced, use:

```elisp
M-x org-snitch-find-references
```

This command lets you select a task via `completing-read`, then leverages `project.el` and `xref` to search your entire codebase for the task's ID. Wait a moment, and an `xref` buffer will pop up displaying the results with file previews across your project.

## License

This project is licensed under the GNU General Public License v3.0 or later. See the [LICENSE](LICENSE) file for details.
