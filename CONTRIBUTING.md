# Contributing to TMC.vim

Thank you for your interest in contributing to TMC.vim! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- Vim 8.2+ or Neovim 0.5+
- Git
- Python 3.x (for vint linter)
- Basic knowledge of VimScript

### Development Setup

1. Fork the repository on GitHub

2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/tmc.vim.git
   cd tmc.vim
   ```

3. Install development dependencies:
   ```bash
   # Install Vader.vim for testing
   git clone https://github.com/junegunn/vader.vim.git ~/.vim/plugged/vader.vim
   
   # Install vint for linting
   pip install vim-vint
   ```

4. Create a branch for your changes:
   ```bash
   git checkout -b feature/my-new-feature
   ```

## Code Style

### VimScript Guidelines

- Use 2 spaces for indentation
- Add `abort` keyword to all functions
- Use descriptive variable names (prefix with `l:` for local, `g:` for global, `s:` for script-local, `a:` for arguments)
- Add comments for complex logic
- Keep functions focused and small
- Use meaningful function names with the `tmc#module#function` pattern

### Example:

```vim
" Good
function! tmc#util#echo_error(msg) abort
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction

" Bad
function! err(m)
  echom a:m
endfunction
```

## Testing

### Running Tests

Run all tests with Vader.vim:

```bash
# Using Vim
vim -Nu NONE -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"

# Using Neovim
nvim --headless -u NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"
```

### Running Linter

```bash
vint autoload/ plugin/
```

### Writing Tests

- Place unit tests in `test/unit/`
- Place integration tests in `test/integration/`
- Use descriptive test names
- Include both positive and negative test cases
- Test both Vim and Neovim when relevant

Example test structure:

```vader
Execute (Test description):
  " Setup
  let expected = 'value'
  
  " Execute
  let result = tmc#some#function()
  
  " Assert
  AssertEqual expected, result
```

## Submitting Changes

### Pull Request Process

1. **Update your branch** with the latest changes from main:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Run tests** and ensure they pass:
   ```bash
   vim -Nu NONE -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
     -c "Vader! test/**/*.vader"
   ```

3. **Run linter** and fix any issues:
   ```bash
   vint autoload/ plugin/
   ```

4. **Commit your changes** with clear messages:
   ```bash
   git commit -m "Add feature X"
   ```
   
   Commit message guidelines:
   - Use present tense ("Add feature" not "Added feature")
   - First line should be 50 characters or less
   - Reference issues and PRs liberally

5. **Push to your fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

6. **Create a Pull Request** on GitHub

### Pull Request Guidelines

- Provide a clear description of the changes
- Reference any related issues
- Include test coverage for new features
- Update documentation if needed
- Ensure CI passes
- Be responsive to feedback

## Project Structure

```
tmc.vim/
├── autoload/
│   ├── tmc.vim           # Backward compatibility layer
│   └── tmc/
│       ├── util.vim      # Utility functions (messaging)
│       ├── core.vim      # Core compatibility shims
│       ├── project.vim   # Project/exercise management
│       ├── course.vim    # Course management
│       ├── exercise.vim  # Exercise management
│       ├── cli.vim       # CLI integration
│       ├── auth.vim      # Authentication
│       ├── ui.vim        # UI components
│       ├── submit.vim    # Exercise submission
│       ├── run_tests.vim # Test execution
│       ├── download.vim  # Exercise download
│       ├── paste.vim     # Paste functionality
│       └── spinner.vim   # Loading spinner
├── plugin/
│   └── tmc.vim          # Plugin entry point, commands
├── doc/
│   └── tmc.txt          # Help documentation
├── test/
│   ├── helpers.vim      # Test utilities
│   ├── unit/            # Unit tests
│   └── integration/     # Integration tests
└── syntax/
    └── tmcresult.vim    # Syntax highlighting
```

## Module Organization

- **util.vim**: Common utilities (error/info messages)
- **project.vim**: Finding exercise roots, parsing IDs, managing projects directory
- **course.vim**: Course listing and management
- **exercise.vim**: Exercise listing and ID extraction
- **core.vim**: Backward compatibility shims (delegates to new modules)

## Reporting Bugs

### Before Submitting a Bug Report

- Check the [existing issues](https://github.com/ukonhattu/tmc.vim/issues)
- Try to reproduce with minimal configuration
- Check the `:TmcStatus` and `:TmcProjectsDir` outputs

### Submitting a Bug Report

Use the bug report template and include:
- Vim/Neovim version (`:version`)
- Operating system
- Plugin version/commit
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

## Feature Requests

We welcome feature requests! Please:
- Check existing issues first
- Clearly describe the feature and its use case
- Explain why it would be useful to most users
- Consider if it can be implemented as a separate plugin

## Questions?

- Open a [discussion](https://github.com/ukonhattu/tmc.vim/discussions)
- Check the [documentation](doc/tmc.txt)
- Read the [README](README.md)

## License

By contributing, you agree that your contributions will be licensed under the GPLv3 License.

## Code of Conduct

- Be respectful and considerate
- Welcome newcomers and help them learn
- Focus on constructive feedback
- Assume good faith

Thank you for contributing to TMC.vim! 🎉

