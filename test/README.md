# TMC.vim Testing Guide

This directory contains the test suite for TMC.vim using Vader.vim.

## Test Structure

```
test/
├── README.md                   # This file
├── helpers.vim                 # Test utilities and mocks
├── unit/                       # Unit tests for individual modules
│   ├── test_util.vader
│   ├── test_project.vader
│   ├── test_course.vader
│   └── test_exercise.vader
└── integration/                # Integration and compatibility tests
    ├── test_vim_neovim_compat.vader
    └── test_workflow.vader
```

## Prerequisites

1. **Vim 8.2+** or **Neovim 0.5+**
2. **Vader.vim** test framework

### Installing Vader.vim

```bash
# For Vim
git clone --depth 1 https://github.com/junegunn/vader.vim.git ~/.vim/plugged/vader.vim

# For Neovim
git clone --depth 1 https://github.com/junegunn/vader.vim.git \
  ~/.local/share/nvim/site/pack/vendor/start/vader.vim
```

## Running Tests

### Run All Tests

**Using Vim:**
```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"
```

**Using Neovim:**
```bash
nvim --headless -u NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader! test/**/*.vader"
```

### Run Specific Test Files

**Unit tests only:**
```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "Vader! test/unit/*.vader"
```

**Integration tests only:**
```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "Vader! test/integration/*.vader"
```

**Single test file:**
```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "Vader! test/unit/test_util.vader"
```

### Interactive Mode

Run tests interactively to see detailed output:

```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \
  -c "Vader test/**/*.vader"
```

(Note: Without the `!` after Vader, it runs in interactive mode)

## Writing Tests

### Test File Template

```vader
" test/unit/test_mymodule.vader
" Description of what this file tests

Before:
  source test/helpers.vim
  call helpers#setup()

After:
  call helpers#teardown()

Execute (Test case description):
  " Arrange
  let expected = 'value'
  
  " Act
  let result = tmc#mymodule#function()
  
  " Assert
  AssertEqual expected, result
```

### Available Assertions

Vader.vim provides these assertions:
- `Assert <condition>` - Assert condition is truthy
- `AssertEqual <expected>, <actual>` - Assert equality
- `AssertNotEqual <expected>, <actual>` - Assert inequality
- `AssertThrows <command>` - Assert command throws error

### Test Helpers

The `test/helpers.vim` file provides:
- `helpers#setup()` - Set up test environment
- `helpers#teardown()` - Clean up after tests
- `helpers#mock_*_response()` - Mock API responses
- `helpers#create_temp_dir()` - Create temporary directory
- `helpers#create_mock_exercise_root()` - Create mock exercise
- Custom assertions

### Best Practices

1. **Isolation**: Each test should be independent
2. **Setup/Teardown**: Use Before/After blocks
3. **Descriptive Names**: Test names should clearly describe what they test
4. **Mock External Calls**: Don't make real network requests
5. **Test Both Success and Failure**: Cover happy path and error cases

### Example Test

```vader
Execute (tmc#project#find_exercise_root should find .tmcproject.yml):
  " Arrange
  let temp_dir = helpers#create_temp_dir()
  let exercise_dir = temp_dir . '/exercise1'
  call helpers#create_mock_exercise_root(exercise_dir)
  call writefile(['test'], exercise_dir . '/test.py')
  
  " Act
  execute 'edit' exercise_dir . '/test.py'
  let root = tmc#project#find_exercise_root()
  
  " Assert
  AssertEqual exercise_dir, root
  
  " Cleanup
  execute 'bwipeout!'
  call delete(temp_dir, 'rf')
```

## Continuous Integration

Tests run automatically on GitHub Actions for:
- Vim 8.2, 9.0
- Neovim 0.5, 0.9, stable
- Ubuntu and macOS

See `.github/workflows/ci.yml` for CI configuration.

## Troubleshooting

### Tests Fail with "E117: Unknown function"

Ensure the plugin is loaded:
```bash
vim -Nu NONE \
  -c "set runtimepath+=.,~/.vim/plugged/vader.vim" \
  -c "runtime plugin/tmc.vim" \  # This line is important!
  -c "Vader! test/**/*.vader"
```

### Tests Hang or Don't Complete

Use `--headless` with Neovim or check for interactive prompts in your tests.

### "Vader not found" Error

Ensure Vader.vim is installed and in your runtimepath:
```bash
ls ~/.vim/plugged/vader.vim/plugin/vader.vim
# or
ls ~/.local/share/nvim/site/pack/vendor/start/vader.vim/plugin/vader.vim
```

## Code Coverage

While VimScript doesn't have built-in coverage tools, ensure:
- All public functions have at least one test
- Both success and error paths are tested
- Edge cases are covered

## Contributing Tests

When contributing:
1. Add tests for new features
2. Add tests for bug fixes (regression tests)
3. Ensure all tests pass before submitting PR
4. Follow the existing test structure and naming conventions

For more information, see [CONTRIBUTING.md](../CONTRIBUTING.md).

