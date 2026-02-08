# Contributing to LocustSocial 🦗

Thank you for your interest in contributing to LocustSocial! This document provides guidelines for contributing to the project.

## 🌟 Ways to Contribute

- **Bug Reports**: Found a bug? Open an issue with detailed reproduction steps
- **Feature Requests**: Have an idea? Share it through GitHub Issues
- **Code Contributions**: Submit pull requests with improvements or new features
- **Documentation**: Help improve our docs, guides, and examples
- **Testing**: Write tests to improve code coverage

## 🚀 Getting Started

### Prerequisites

- **iOS Development**: Xcode 15.0+, macOS 13.0+
- **Backend Development**: Python 3.11+, Docker, PostgreSQL
- **Git**: Familiarity with Git workflows

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/LocustSocial.git
   cd LocustSocial
   ```
3. Add upstream remote:
   ```bash
   git remote add upstream https://github.com/LocustSocial/LocustSocial.git
   ```

## 📝 Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

**Branch naming conventions:**
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Adding tests

### 2. Make Changes

- Write clean, readable code
- Follow Swift style guide for iOS code
- Follow PEP 8 for Python code
- Add comments for complex logic
- Update documentation as needed

### 3. Test Your Changes

**iOS:**
```bash
# Run in Xcode with Cmd+U
# Or use command line:
xcodebuild test -scheme LocustSocial -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Backend:**
```bash
cd backend
pytest tests/
```

### 4. Commit Your Changes

Write clear, descriptive commit messages:

```bash
git add .
git commit -m "feat: add image carousel to post cards"
```

**Commit message format:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Code style changes (formatting, etc.)
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance tasks

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub with:
- Clear title describing the change
- Detailed description of what and why
- Screenshots/videos for UI changes
- Link to related issues

## 🎨 Code Style Guidelines

### Swift/SwiftUI

- Use meaningful variable and function names
- Prefer `let` over `var` when possible
- Use MARK comments to organize code
- Follow Apple's Swift API Design Guidelines
- SwiftUI views should be small and focused

Example:
```swift
// MARK: - View
struct PostCardView: View {
    let post: Post
    @State private var isLiked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Content here
        }
    }
}
```

### Python

- Follow PEP 8 style guide
- Use type hints for function signatures
- Write docstrings for public functions
- Keep functions focused and small

Example:
```python
async def create_post(
    title: str,
    body: str,
    image: Optional[bytes] = None
) -> Post:
    """
    Create a new post with optional image.
    
    Args:
        title: Post title
        body: Post content
        image: Optional image bytes
        
    Returns:
        Created post object
    """
    # Implementation
```

## 🧪 Testing Guidelines

### iOS Tests

- Unit tests for business logic
- UI tests for critical user flows
- Test both success and error cases
- Mock external dependencies

### Backend Tests

- Test all API endpoints
- Test database operations
- Test edge cases and error handling
- Use pytest fixtures for setup

## 📚 Documentation

- Update README.md for major changes
- Add inline comments for complex code
- Document new API endpoints
- Update CHANGELOG.md

## 🐛 Reporting Bugs

When reporting bugs, include:

1. **Description**: Clear description of the bug
2. **Steps to Reproduce**: Numbered steps to reproduce
3. **Expected Behavior**: What should happen
4. **Actual Behavior**: What actually happens
5. **Environment**: iOS version, Xcode version, etc.
6. **Screenshots**: If applicable

## 💡 Feature Requests

For feature requests, describe:

1. **Problem**: What problem does this solve?
2. **Proposed Solution**: Your suggested implementation
3. **Alternatives**: Other solutions you considered
4. **Additional Context**: Screenshots, mockups, etc.

## 🔒 Security Issues

**Do not** open public issues for security vulnerabilities.

Instead, email: security@locustsocial.com

## 📋 Pull Request Checklist

Before submitting, ensure:

- [ ] Code builds without errors
- [ ] All tests pass
- [ ] New code has test coverage
- [ ] Documentation is updated
- [ ] Commit messages follow conventions
- [ ] Branch is up to date with main
- [ ] No merge conflicts

## 🎯 Code Review Process

1. **Automated Checks**: CI/CD runs tests and linters
2. **Peer Review**: At least one maintainer reviews code
3. **Feedback**: Address review comments
4. **Approval**: Once approved, changes can be merged
5. **Merge**: Squash and merge to main branch

## 🌍 Community Guidelines

- Be respectful and inclusive
- Welcome newcomers
- Provide constructive feedback
- Follow our [Code of Conduct](CODE_OF_CONDUCT.md)

## 📞 Questions?

- Open a [GitHub Discussion](https://github.com/LocustSocial/LocustSocial/discussions)
- Join our Discord: [discord.gg/locustsocial](https://discord.gg/locustsocial)
- Email: dev@locustsocial.com

## 🙏 Thank You!

Every contribution, no matter how small, makes a difference. Thank you for helping make LocustSocial better!

---

**Happy Coding! 🦗**
