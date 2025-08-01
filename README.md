# TMC-Vim
----
THIS IS A WIP VERSION.  
However, it is minimally usable. You can login, select org, select course, download exercises, run tests andsubmit exercises. Readme might be a bit behind, so message me / open issue if you have problems.

Tested only with neovim so far. I will test it with vim too at some point and intend to keep it compatible with both.

----

`tmc.vim` is a simple Vim plugin that integrates the
[tmc‑langs‑cli](https://github.com/rage/tmc-langs-rust/tree/main/crates/tmc-langs-cli) into Vim.  It allows you to
log in to the Test‑My‑Code service, list courses and exercises, download
exercise templates and submit completed exercises – all without leaving the
editor.

## Installation

1. **No separate installation of the `tmc‑langs‑cli` binary is required.**
   On first use, the plugin attempts to download a suitable prebuilt
   `tmc‑langs‑cli` into a cache directory based on your operating system and
   architecture.  The default version downloaded is **`0.38.1`**, which is a
   recent release of the CLI.  To ensure integrity, the plugin
   downloads the corresponding `*.sha256` file and verifies the
   SHA‑256 checksum of the binary; if the checksum does not match, the file
   is discarded and an error is reported.  If you prefer to use a different
   version or have already installed your own binary, set
   `g:tmc_cli_path` in your `.vimrc` to point to the desired executable.  You
   can also override the downloaded version by setting
   `g:tmc_cli_version` (e.g. `let g:tmc_cli_version = '0.38.1'`).  When
   `g:tmc_cli_path` is set and points to a readable file, the plugin will
   never attempt to download a binary.

2. Place this plugin in your runtime path.  If you use a plugin manager such as
   [vim‑plug](https://github.com/junegunn/vim-plug), add a line like this to
   your `.vimrc`:

   ```vim
   Plug 'ukonhattu/tmc.vim'
   ```

   [Lazy](https://https://github.com/folke/lazy.nvim) (neovim)
   ```lua
   { 'ukonhattu/tmc.vim' }
   ```

   Or manually copy the `vim‑tmc` directory into `~/.vim/pack/tmc/start`.

3. Restart Vim or run `:source $MYVIMRC` to load the plugin.  The first time
   you run a `:Tmc*` command, the plugin will download the CLI and store it
   in a cache directory (typically under `~/.local/share/tmc` or `~/.vim/tmc`).

## Commands

| Command | Description |
|---|---|
| `:TmcLogin [email]` | Logs into the TMC server.  Prompts for a password.  If the email is omitted you are asked to enter it interactively.  The CLI stores your OAuth token. |
| `:TmcCourses` | Lists available courses for the current organisation (default `mooc`).  Change the organisation slug with `:TmcSetOrg <slug>`, where `<slug>` is accepted by the CLI (e.g. `mooc`, `hy`) |
| `:TmcExercises <courseId>` | Lists exercises for a course.  Use `:TmcCourses` to discover course IDs. |
| `:TmcDownload <exerciseId> ...` | Downloads or updates one or more exercises using the `download‑or‑update‑course‑exercises` command.  The student file policy prevents overwriting your work. |
| `:TmcSubmit <exerciseId> <path>` | Submits the exercise located at the given path.  Blocks until results are returned unless the CLI is invoked with `--dont-block`. |
| `:TmcRunTests` | Runs tests for the exercise containing the current buffer.  The plugin calls the CLI’s `run-tests` subcommand with the exercise directory as `--exercise-path` and displays the output in a scratch buffer. |
| `:TmcSubmitCurrent` | Submits the exercise containing the current buffer.  The exercise ID is determined by reading `course_config.toml` in the course root to map the current exercise slug to its numeric ID.  If no mapping is found, you are prompted to enter the ID.  Uses the same submission command as `:TmcSubmit`. |
| `:TmcSetOrg <slug>` | Changes the organisation slug used by `:TmcCourses`.  The slug corresponds to the parameter of the GetCourses command. |
| `:TmcPickCourse` | Opens a popup menu to select an organisation (if not set) and then a course.  Once a course is selected, its exercises are listed automatically. |
|`:TmcPickOrg` | Opens a popip menu select an organisation.
|`:TmcCdCourse`| Change vim's current working directory to the last picked course
| `:Tmc <subcommand> [args...]` | Runs an arbitrary `tmc-langs-cli` command. If running  `tmc` or `mooc` subcommand, --client-name and --client-version are automatically added to the command. Mooc command has not been tested yet.|

Additional variables:

* `g:tmc_cli_path` – override the name/path of the CLI binary (default
  `tmc‑langs‑cli`).
* `g:tmc_organization` – default organisation slug used by `:TmcCourses`.  Initially set to `mooc`.
* `g:tmc_disable_default_mappings` – if set to a non‑zero value, disables the default key mappings (`<leader>tt` to run tests and `<leader>ts` to submit).

## Notes

* To list courses in organisations other than `mooc`, call `:TmcSetOrg` or set
  `g:tmc_organization` in your `vimrc`.
* When working inside a downloaded exercise, you can run tests and submit
  without remembering exercise IDs.  By default `<leader>tt` calls
  `:TmcRunTests` and `<leader>ts` calls `:TmcSubmitCurrent`.  These mappings
  can be disabled by setting `g:tmc_disable_default_mappings`.
* Current Workflow is to run `:TmcPickCourse` -> `:TmcCdCourse`, navigate however you want to the exercise, when in exercise you can run `<leader>tt` to run tests and `<leader>ts` to submit. (or `:TmcRunRests` and `:TmcSubmitCurrent`)

## License

This plugin is distributed under the GPLv3 license.
