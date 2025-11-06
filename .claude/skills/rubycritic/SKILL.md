---
name: rubycritic
description: Integrate RubyCritic to analyze Ruby code quality and maintain high standards throughout development. Use when working on Ruby projects to check code smells, complexity, and duplication. Triggers include creating/editing Ruby files, refactoring code, reviewing code quality, or when user requests code analysis or quality checks.
---

# RubyCritic Code Quality Integration

This skill integrates RubyCritic to maintain high code quality standards in Ruby projects during Claude Code sessions.

## Quick Start

When working on Ruby code, periodically run RubyCritic to check code quality:

```bash
scripts/check_quality.sh [path/to/ruby/files]
```

If no path is provided, it analyzes the current directory.

## Workflow Integration

### When to Run RubyCritic

Run quality checks:

- After creating new Ruby files or classes
- After significant refactoring
- Before committing code
- When user explicitly requests code quality analysis
- After implementing complex methods or logic

### Interpreting Results

RubyCritic provides:

- **Overall Score**: Project-wide quality rating (0-100)
- **File Ratings**: A-F letter grades per file
- **Code Smells**: Specific issues detected by Reek
- **Complexity**: Flog scores indicating method complexity
- **Duplication**: Flay scores showing code duplication

### Quality Thresholds

Aim for:

- **Overall Score**: 95+ (excellent), 90+ (good), 80+ (acceptable)
- **File Ratings**: A or B ratings for all files
- **No Critical Smells**: Address any high-priority issues immediately

### Responding to Issues

When RubyCritic identifies problems:

1. **Review the console output** for specific issues
2. **Prioritize critical smells** (complexity, duplication, unclear naming)
3. **Refactor incrementally** - fix issues one at a time
4. **Re-run analysis** after each fix to verify improvement
5. **Explain changes** to the user if quality improves significantly

## Installation Handling

The check_quality.sh script automatically:

- Detects if RubyCritic is installed
- Installs it if missing (with user awareness)
- Uses bundler if Gemfile is present
- Falls back to system gem installation

## Configuration

RubyCritic respects `.rubycritic.yml` if present in the project. For custom configuration, create this file with options like:

```yaml
minimum_score: 95
formats:
  - console
paths:
  - 'app/'
  - 'lib/'
no_browser: true
```

## Output Formats

The script uses console format by default for inline feedback. For detailed reports:

- HTML report: `rubycritic --format html [paths]`
- JSON output: `rubycritic --format json [paths]`

## Best Practices

1. **Run early and often** - Catch issues before they multiply
2. **Address issues immediately** - Don't let technical debt accumulate
3. **Explain to users** - When fixing quality issues, briefly explain what was improved
4. **Set baselines** - On new projects, establish quality standards early
5. **CI mode** - For comparing branches: `--mode-ci --branch main`

## Bundled Resources

- **scripts/check_quality.sh**: Automated quality check with installation handling
