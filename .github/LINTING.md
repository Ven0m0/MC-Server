# Linting and Formatting

This repository uses automated linting and formatting for configuration files to maintain code quality and consistency.

## What Gets Linted

The MegaLinter workflow automatically checks and formats:

- **YAML/YML** files (`.yml`, `.yaml`)
- **TOML** files (`.toml`)
- **JSON** files (`.json`, `.json5`, `.jsonc`)
- **Properties** files (`.properties`)

## Linters Used

### YAML
- **yamllint**: Validates YAML syntax and style
- **prettier**: Auto-formats YAML files

### JSON
- **jsonlint**: Validates JSON syntax
- **prettier**: Auto-formats JSON files
- **npm-package-json-lint**: Validates package.json specifically

### TOML
- **taplo**: Formats and validates TOML files

## Configuration Files

- **`.yamllint.yml`**: YAML linting rules
- **`.prettierrc.yml`**: Formatting rules for all file types
- **`.editorconfig`**: Editor-agnostic formatting rules
- **`.megalinter.yml`**: MegaLinter configuration

## Auto-Fix Behavior

The workflow is configured to **automatically fix** formatting issues:

- **On Push**: Fixes are committed directly to the branch
- **On Pull Request**: May create a separate PR with fixes

## Running Locally

### Install Dependencies

```bash
# Install yamllint
pip install yamllint

# Install prettier and plugins
npm install -g prettier

# Install taplo
cargo install taplo-cli
```

### Run Linters

```bash
# Lint YAML files
yamllint config/

# Format all files with Prettier
prettier --write "**/*.{yml,yaml,json,toml}"

# Format TOML files with Taplo
taplo fmt config/**/*.toml
```

### Run MegaLinter Locally

```bash
# Using Docker
docker run --rm \
  -v $(pwd):/tmp/lint \
  oxsecurity/megalinter:v7

# Using npm
npx mega-linter-runner --flavor documentation
```

## Configuration Details

### YAML Rules (.yamllint.yml)

- Max line length: 120 characters (warning)
- Indentation: 2 spaces
- Allows inline mappings and sequences
- Truthy values allowed: `true`, `false`, `yes`, `no`, `on`, `off`
- Document start (`---`) not required

### Prettier Rules (.prettierrc.yml)

- Print width: 120 characters
- Tab width: 2 spaces
- No semicolons
- Double quotes
- No trailing commas
- LF line endings

### Editor Config (.editorconfig)

- Encoding: UTF-8
- Line endings: LF
- Trim trailing whitespace: enabled
- Insert final newline: enabled
- Indent: 2 spaces (for config files)

## Bypass Linting

If you need to bypass linting for a specific commit:

```bash
git commit --no-verify -m "Your message"
```

**Note**: This is not recommended and should only be used in exceptional cases.

## CI/CD Integration

The linting workflow runs automatically on:

- Pushes to `main`, `master`, or `claude/**` branches
- Pull requests to `main` or `master`
- Only when config files are modified

## Troubleshooting

### Workflow Not Running

Check that your changes include files matching:
- `**/*.yml`, `**/*.yaml`
- `**/*.toml`
- `**/*.json`, `**/*.json5`, `**/*.jsonc`
- `**/*.properties`

### Linting Errors

1. Check the MegaLinter report artifacts
2. Review the specific linter output
3. Fix issues locally and push again
4. Or let auto-fix create a PR with corrections

### False Positives

Update the relevant config file:
- YAML issues: Edit `.yamllint.yml`
- Formatting issues: Edit `.prettierrc.yml`
- All issues: Edit `.megalinter.yml`

## Additional Resources

- [MegaLinter Documentation](https://megalinter.io/)
- [yamllint Documentation](https://yamllint.readthedocs.io/)
- [Prettier Documentation](https://prettier.io/)
- [Taplo Documentation](https://taplo.tamasfe.dev/)
- [EditorConfig](https://editorconfig.org/)
