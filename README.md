# TMC-Vim

[![CI](https://github.com/ukonhattu/tmc.vim/workflows/CI/badge.svg)](https://github.com/ukonhattu/tmc.vim/actions)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A Vim/Neovim plugin that integrates [tmc-langs-cli](https://github.com/rage/tmc-langs-rust/tree/main/crates/tmc-langs-cli) 
for working with Test-My-Code exercises directly from your editor.

## Features

- Authentication with TMC server
- Interactive course and exercise browsing
- Automatic exercise download and updates
- Local test execution with formatted results
- Exercise submission with instant feedback
- Vim 8.2+ and Neovim 0.5+ support
- Multiple UI backends (Telescope, fzf.vim, native popups)
- Automatic CLI binary download with SHA-256 verification

## Quick Start

1. Install the plugin with your plugin manager
2. Login to TMC: `:TmcLogin your@email.com`
3. Select a course: `:TmcPickCourse`
4. Navigate to an exercise and run tests: `<leader>tt` or `:TmcRunTests`
5. Submit your solution: `<leader>ts` or `:TmcSubmit`

See the [Commands](#commands) section for detailed usage.

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
| `:TmcPickCourse` | Opens a menu to select a course.  Once a course is selected, its exercises are downloaded automatically and then changes working directory to the course's directory. Run this too if you want to update the exercises or download new ones. (Will add command for those later).  |
|`:TmcPickOrg` | Opens a popup menu to select an organisation.
|`:TmcCdCourse`| Change Vim's current working directory to the last picked course
| `:Tmc <subcommand> [args...]` | Runs an arbitrary `tmc-langs-cli` command. If running  `tmc` or `mooc` subcommand, --client-name and --client-version are automatically added to the command. Mooc command has not been tested yet.|

## Configuration

### Plugin Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `g:tmc_cli_path` | auto-download | Path to tmc-langs-cli binary. Set to override automatic download. |
| `g:tmc_cli_version` | `'0.38.1'` | Version to download automatically if binary not found. |
| `g:tmc_organization` | `'mooc'` | Default organization slug for course listings. |
| `g:tmc_disable_default_mappings` | `0` | Set to `1` to disable default `<leader>tt` and `<leader>ts` mappings. |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `TMC_LANGS_DEFAULT_PROJECTS_DIR` | Override default exercises download location. |

### Example Configuration

```vim
" Use custom CLI binary
let g:tmc_cli_path = '/usr/local/bin/tmc-langs-cli'

" Use different organization
let g:tmc_organization = 'hy'

" Disable default mappings and set custom ones
let g:tmc_disable_default_mappings = 1
nmap <F5> <Plug>(tmc-run-tests)
nmap <F6> <Plug>(tmc-submit-current)
```

## Notes

* To list courses in organisations other than `mooc`, call `:TmcSetOrg` or set
  `g:tmc_organization` in your `vimrc`.
* When working inside a downloaded exercise, you can run tests and submit
  without remembering exercise IDs.  By default `<leader>tt` calls
  `:TmcRunTests` and `<leader>ts` calls `:TmcSubmitCurrent`.  These mappings
  can be disabled by setting `g:tmc_disable_default_mappings`.
* Current Workflow is to run `:TmcPickCourse` (This will cd to course directory too) (Now it defaults to mooc org, run `TmcPickOrg` to change), navigate however you want to the exercise, when in exercise you can run `<leader>tt` to run tests and `<leader>ts` to submit. (or `:TmcRunTests` and `:TmcSubmit`)

## Troubleshooting

### CLI Download Issues
If the plugin fails to download `tmc-langs-cli`, you can:
1. Manually download the binary from [tmc-langs-rust releases](https://github.com/rage/tmc-langs-rust/releases)
2. Set `g:tmc_cli_path` to point to your downloaded binary

### Projects Directory Issues
If you see errors about the projects directory:
1. Set the environment variable: `export TMC_LANGS_DEFAULT_PROJECTS_DIR=~/tmc-exercises`
2. Or run: `tmc-langs-cli settings move-projects-dir --client-name tmc_vim ~/tmc-exercises`

### Authentication Issues
If login fails:
- Ensure you're using the correct email and password
- Check your network connection
- Try running `:TmcLogout` and then `:TmcLogin` again

## Testing

This plugin includes a comprehensive test suite using Vader.vim. To run tests:

```bash
# Install Vader.vim
git clone --depth 1 https://github.com/junegunn/vader.vim.git ~/.vim/plugged/vader.vim

# Run tests with Vim
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"

# Run tests with Neovim
nvim --headless -u NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"
```

See [test/README.md](test/README.md) for detailed testing documentation.

## Development

For information on contributing, code structure, and development setup, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Project Structure

```
autoload/tmc/
├── util.vim          - Utility functions (messaging)
├── project.vim       - Project and exercise management
├── course.vim        - Course listing and data
├── exercise.vim      - Exercise management
├── cli.vim           - CLI integration
├── auth.vim          - Authentication
├── ui.vim            - Interactive UI components
├── submit.vim        - Exercise submission
├── run_tests.vim     - Test execution
├── download.vim      - Exercise downloads
└── ...
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Setting up the development environment
- Running tests and linting
- Submitting pull requests
- Code style conventions

## Documentation

- **User Guide**: `:help tmc` (after installation)
- **Testing Guide**: [test/README.md](test/README.md)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
- **Refactoring Summary**: [REFACTORING_SUMMARY.md](REFACTORING_SUMMARY.md)

## License

This plugin is distributed under the GPLv3 license.
