# Patch Requirements Script

A Bash script to automatically update package versions in `requirements.txt` files across multiple repositories in a GitHub organization. This tool is particularly useful for applying security patches and updates across many projects simultaneously.

## Features

- 🔍 **Organization-wide scanning**: Automatically discovers and processes all repositories in a GitHub organization
- 📦 **Package-specific updates**: Target specific packages for version updates
- 🔒 **Version filtering**: Option to only update packages that meet minimum version requirements
- 🌿 **Branch strategy support**: Two different workflow strategies (dev branch and main branch)
- 🎨 **Colorized output**: Clear, colored terminal output for better readability
- ✅ **Interactive confirmation**: Review changes before applying (with auto-approve option)
- 🔗 **Pull request creation**: Automatic PR creation for main branch strategy
- 🧹 **Cleanup**: Automatic temporary directory cleanup

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com/) - Must be installed and authenticated
- Git
- Bash shell (macOS/Linux)
- Access to the GitHub organization repositories

## Installation

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd patch-script
   ```

2. Make the script executable:
   ```bash
   chmod +x patch_requirements.sh
   ```

3. Ensure GitHub CLI is installed and authenticated:
   ```bash
   # Install GitHub CLI (if not already installed)
   # On macOS:
   brew install gh
   
   # Authenticate with GitHub
   gh auth login
   ```

## Usage

### Basic Syntax

```bash
./patch_requirements.sh -o <organization> -p <package> -r <target_version> [OPTIONS]
```

### Required Arguments

- `-o <organization>`: GitHub organization name
- `-p <package>`: Package name to check and update
- `-r <target_version>`: Target version to update packages to

### Optional Arguments

- `-v <minimum_version>`: Minimum version required for qualification (if not set, all packages qualify)
- `-y`: Auto-approve all changes (skip user confirmation)
- `--main`: Use main branch strategy (create PR for manual merge). Default is dev branch strategy
- `-h`: Display help message

## Branch Strategies

### Dev Branch Strategy (Default)

- Searches for repositories with a `dev` branch
- Commits updates directly to the `dev` branch
- Suitable for development workflows where changes can be applied directly

### Main Branch Strategy (`--main` flag)

- Searches for repositories with a `main` branch
- Creates a feature branch from `main`
- Creates a pull request for manual review and merge
- Suitable for production workflows requiring code review

## Examples

### Update all packages to a specific version
```bash
./patch_requirements.sh -o myorg -p requests -r 2.28.0
```

### Update only packages that meet minimum version requirement
```bash
./patch_requirements.sh -o myorg -p requests -r 11.3.0 -v 11.2.0
```

### Use main branch strategy with auto-approval
```bash
./patch_requirements.sh -o myorg -p django -r 4.2.1 -v 4.1.0 --main -y
```

### Security patch example
```bash
./patch_requirements.sh -o mycompany -p pillow -r 9.5.0 -v 9.0.0 -y
```

## How It Works

1. **Repository Discovery**: Fetches all repositories from the specified GitHub organization
2. **Branch Selection**: Determines which branch to work with based on the chosen strategy
3. **Requirements Analysis**: Checks each repository for `requirements.txt` and the target package
4. **Version Comparison**: Compares current package version with target and minimum versions
5. **Update Process**: Updates the package version if criteria are met
6. **Change Review**: Shows diff and asks for confirmation (unless auto-approved)
7. **Commit & Push**: Commits changes and pushes to appropriate branch
8. **PR Creation**: Creates pull request if using main branch strategy

## Output

The script provides colorized output with clear indicators:

- ✓ **Green**: Success messages
- ⚠ **Yellow**: Warnings and prompts
- ✗ **Red**: Error messages
- ℹ **Blue**: Information messages
- 🔗 **Purple**: Pull request links

## Safety Features

- **Exact package matching**: Prevents partial matches that could affect unintended packages
- **Package name validation**: Rejects package names that are too short
- **Version validation**: Uses proper semantic version comparison
- **Confirmation prompts**: Shows changes before applying (unless auto-approved)
- **Automatic cleanup**: Removes temporary directories on exit

## Error Handling

The script includes comprehensive error handling for common scenarios:

- Missing or invalid GitHub CLI authentication
- Repository access issues
- Missing `requirements.txt` files
- Package not found in requirements
- Git operation failures
- Pull request creation failures

## Limitations

- Only works with `requirements.txt` files (not `pyproject.toml`, `Pipfile`, etc.)
- Designed for Python projects using pip
- Requires repositories to have either `dev` or `main` branches (depending on strategy)
- Version comparison works with standard semantic versioning formats
