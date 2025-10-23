## Description
<!-- Provide a clear and concise description of your changes -->

## Type of Change
<!-- Mark the relevant option with an 'x' -->
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Code refactoring
- [ ] Performance improvement
- [ ] Test coverage improvement

## Related Issues
<!-- Link to related issues, e.g., "Fixes #123" or "Relates to #456" -->
Fixes #

## Changes Made
<!-- List the main changes in this PR -->
- Change 1
- Change 2
- Change 3

## Testing
<!-- Describe the tests you ran to verify your changes -->

### Test Configuration
- OS: [e.g. Ubuntu 22.04]
- Vim/Neovim version: [e.g. Neovim 0.9.0]

### Test Coverage
- [ ] Added unit tests for new functionality
- [ ] Added integration tests
- [ ] All existing tests pass
- [ ] Tested manually in Vim
- [ ] Tested manually in Neovim

### Test Commands Run
```bash
# List the test commands you ran
vim -Nu NONE -c "Vader! test/**/*.vader"
vint autoload/ plugin/
```

## Documentation
- [ ] Updated README.md (if needed)
- [ ] Updated doc/tmc.txt (if needed)
- [ ] Updated CONTRIBUTING.md (if needed)
- [ ] Added/updated code comments

## Code Quality
- [ ] My code follows the project's code style guidelines
- [ ] I have performed a self-review of my own code
- [ ] I have commented my code, particularly in hard-to-understand areas
- [ ] My changes generate no new warnings or errors
- [ ] Linter passes without errors (`vint autoload/ plugin/`)

## Breaking Changes
<!-- If this is a breaking change, describe what breaks and how to migrate -->
N/A or:
- Breaking change 1: How to migrate
- Breaking change 2: How to migrate

## Screenshots/Demos
<!-- If applicable, add screenshots or demo GIFs to help explain your changes -->

## Checklist
- [ ] I have read the CONTRIBUTING.md document
- [ ] My code follows the code style of this project
- [ ] I have added tests that prove my fix is effective or that my feature works
- [ ] All new and existing tests pass
- [ ] I have updated the documentation accordingly
- [ ] I have checked my code and corrected any misspellings

## Additional Notes
<!-- Add any additional notes or context about the PR here -->

