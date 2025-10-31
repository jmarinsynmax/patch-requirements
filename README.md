# Patch Requirements Script

A Bash script to automatically update package versions in `requirements.txt` files across multiple repositories in a GitHub organization. This tool is particularly useful for applying security patches and updates across many projects simultaneously.

## Features

- 🔍 **Organization-wide scanning**: Automatically discovers and processes all repositories in a GitHub organization
- 📦 **Package-specific updates**: Target specific packages for version updates
- � **Multi-package support**: Update multiple packages from a file in a single run
- �🔒 **Version filtering**: Option to only update packages that meet minimum version requirements (single-package mode)
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

**Single Package Mode:**
```bash
./patch_requirements.sh -o <organization> -p <package> -r <target_version> [OPTIONS]
```

**Multi-Package Mode:**
```bash
./patch_requirements.sh -o <organization> -f <packages_file> [OPTIONS]
```

### Required Arguments

- `-o <organization>`: GitHub organization name

### Single Package Mode Arguments

- `-p <package>`: Package name to check and update
- `-r <target_version>`: Target version to update packages to
- `-v <minimum_version>`: (Optional) Minimum version required for qualification

### Multi-Package Mode Arguments

- `-f <packages_file>`: Path to file containing package,version pairs (one per line)

**Packages File Format:**
```
# Comments start with # and are ignored
# Format: package_name, version

fastapi, 0.120.4
starlette, 0.49.1
requests, 2.31.0
```

### Optional Arguments

- `-y`: Auto-approve all changes (skip user confirmation)
- `--main`: Use main branch strategy (create PR for manual merge). Default is dev branch strategy
- `-h`: Display help message

**Note:** You must use either single package mode (`-p` and `-r`) OR multi-package mode (`-f`), not both.

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

### Single Package Mode

#### Update all packages to a specific version
```bash
./patch_requirements.sh -o myorg -p requests -r 2.28.0
```

#### Update only packages that meet minimum version requirement
```bash
./patch_requirements.sh -o myorg -p requests -r 11.3.0 -v 11.2.0
```

#### Use main branch strategy with auto-approval
```bash
./patch_requirements.sh -o myorg -p django -r 4.2.1 -v 4.1.0 --main -y
```

#### Security patch example
```bash
./patch_requirements.sh -o mycompany -p pillow -r 9.5.0 -v 9.0.0 -y
```

### Multi-Package Mode

#### Update multiple packages from a file
```bash
./patch_requirements.sh -o myorg -f packages.txt
```

#### Update multiple packages with auto-approval
```bash
./patch_requirements.sh -o myorg -f packages.txt -y
```

#### Update multiple packages using main branch strategy
```bash
./patch_requirements.sh -o myorg -f packages.txt --main -y
```

#### Example packages.txt file
```
# Security updates for multiple packages
fastapi, 0.120.4
starlette, 0.49.1
pydantic, 2.10.3
uvicorn, 0.34.0
```

## How It Works

1. **Mode Selection**: Determines whether to run in single-package or multi-package mode
2. **Package Loading**: Loads package(s) and target version(s) from arguments or file
3. **Repository Discovery**: Fetches all repositories from the specified GitHub organization
4. **Branch Selection**: Determines which branch to work with based on the chosen strategy
5. **Requirements Analysis**: Checks each repository for `requirements.txt` and the target package(s)
6. **Version Comparison**: Compares current package version with target (and minimum version in single-package mode)
7. **Update Process**: Updates the package version(s) if criteria are met
8. **Change Review**: Shows diff and asks for confirmation (unless auto-approved)
9. **Commit & Push**: Commits changes and pushes to appropriate branch
10. **PR Creation**: Creates pull request if using main branch strategy

### Multi-Package Mode Behavior

When using multi-package mode (`-f` flag):
- All packages specified in the file are processed for each repository
- Only packages found in the repository's `requirements.txt` are updated
- If a package is already at the target version, it's skipped
- A single commit is created with all applicable changes per repository
- The commit message lists all updated packages

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
