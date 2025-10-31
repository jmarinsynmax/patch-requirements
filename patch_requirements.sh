#!/bin/bash

# Script to update package versions in requirements.txt across multiple repositories
# This script uses GitHub CLI (gh) to interact with repositories

set -e

# Color definitions for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored text
print_color() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to print section headers
print_header() {
    echo
    print_color "$CYAN" "======================================================="
    print_color "$CYAN$BOLD" "$1"
    print_color "$CYAN" "======================================================="
}

# Function to print success messages
print_success() {
    print_color "$GREEN" "✓ $1"
}

# Function to print error messages
print_error() {
    print_color "$RED" "✗ $1"
}

# Function to print warning messages
print_warning() {
    print_color "$YELLOW" "⚠ $1"
}

# Function to print info messages
print_info() {
    print_color "$BLUE" "ℹ $1"
}

# Function to print PR links with highlighting
print_pr_link() {
    print_color "$PURPLE$BOLD" "🔗 Pull Request: $1"
}

# Function to display usage information
usage() {
    print_color "$WHITE$BOLD" "Usage: $0 -o <organization> [-p <package> -r <target_version> [-v <minimum_version>] | -f <packages_file>] [-y] [--main]"
    echo
    print_color "$YELLOW" "Required Arguments:"
    print_color "$WHITE" "  -o: GitHub organization name"
    echo
    print_color "$YELLOW" "Single Package Mode:"
    print_color "$WHITE" "  -p: Package name to check and update"
    print_color "$WHITE" "  -r: Target version to update packages to"
    print_color "$WHITE" "  -v: Minimum version required for qualification (optional)"
    echo
    print_color "$YELLOW" "Multi-Package Mode:"
    print_color "$WHITE" "  -f: Path to file containing package,version pairs (one per line)"
    print_color "$WHITE" "      Format: package_name, version"
    print_color "$WHITE" "      Example file contents:"
    print_color "$WHITE" "        fastapi, 0.120.4"
    print_color "$WHITE" "        starlette, 0.49.1"
    echo
    print_color "$YELLOW" "Optional Arguments:"
    print_color "$WHITE" "  -y: Auto-approve all changes (skip user confirmation)"
    print_color "$WHITE" "  --main: Use main branch strategy (create PR for manual merge). Default is dev branch strategy"
    print_color "$WHITE" "  -h: Display this help message"
    echo
    print_color "$CYAN" "Examples:"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 2.28.0                    # Update single package to 2.28.0"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0          # Update packages >= 11.2.0 to 11.3.0"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0 --main   # Same but use main branch strategy"
    print_color "$WHITE" "  $0 -o myorg -f packages.txt                          # Update multiple packages from file"
    print_color "$WHITE" "  $0 -o myorg -f packages.txt --main -y                # Update multiple packages (auto-approve)"
    echo
    print_color "$YELLOW" "Note: Use either single package mode (-p -r) or multi-package mode (-f), not both."
    exit 1
}

# Initialize variables
USE_MAIN_STRATEGY=false
TARGET_VERSION_ARG=""
MIN_VERSION=""
PACKAGES_FILE=""

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o)
            ORG="$2"
            shift 2
            ;;
        -p)
            PACKAGE="$2"
            shift 2
            ;;
        -v)
            MIN_VERSION="$2"
            shift 2
            ;;
        -r)
            TARGET_VERSION_ARG="$2"
            shift 2
            ;;
        -f)
            PACKAGES_FILE="$2"
            shift 2
            ;;
        -y)
            AUTO_APPROVE=true
            shift
            ;;
        --main)
            USE_MAIN_STRATEGY=true
            shift
            ;;
        -h)
            usage
            ;;
        *)
            echo "Unknown option: $1" 1>&2
            usage
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$ORG" ]; then
    print_error "Missing required argument: organization (-o)"
    usage
fi

# Validate that either single package mode or multi-package mode is used
if [ -n "$PACKAGES_FILE" ]; then
    # Multi-package mode
    if [ -n "$PACKAGE" ] || [ -n "$TARGET_VERSION_ARG" ] || [ -n "$MIN_VERSION" ]; then
        print_error "Cannot use -f (packages file) together with -p, -r, or -v options."
        print_warning "Use either single package mode (-p -r) or multi-package mode (-f), not both."
        usage
    fi
    
    # Check if file exists and is readable
    if [ ! -f "$PACKAGES_FILE" ]; then
        print_error "Packages file not found: $PACKAGES_FILE"
        exit 1
    fi
    
    if [ ! -r "$PACKAGES_FILE" ]; then
        print_error "Cannot read packages file: $PACKAGES_FILE"
        exit 1
    fi
    
    print_info "Running in multi-package mode with file: $PACKAGES_FILE"
else
    # Single package mode
    if [ -z "$PACKAGE" ] || [ -z "$TARGET_VERSION_ARG" ]; then
        print_error "Missing required arguments for single package mode."
        print_warning "Required: -p (package) and -r (target version)"
        print_info "Or use -f to specify a packages file for multi-package mode."
        usage
    fi
    
    print_info "Running in single package mode"
fi

# For single package mode, validate package name length
if [ -n "$PACKAGE" ]; then
    # Check if package name is reasonable (to avoid partial matches)
    if [ ${#PACKAGE} -lt 2 ]; then
        print_error "Package name '$PACKAGE' is too short and might cause incorrect matches."
        print_warning "Please provide a more specific package name."
        exit 1
    fi
fi

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed. Please install it first."
    print_info "Visit https://cli.github.com/ for installation instructions."
    exit 1
fi

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
    print_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
    exit 1
fi

# Create a temporary directory for repository operations
TEMP_DIR=$(mktemp -d)
print_info "Created temporary directory: $TEMP_DIR"

# Cleanup function to remove temporary directory on exit
cleanup() {
    print_info "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

# Register cleanup function to run on exit
trap cleanup EXIT

# Function to parse packages file and return array of package,version pairs
parse_packages_file() {
    local file=$1
    declare -a packages_array
    
    print_info "Parsing packages file: $file"
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # Parse package and version (expecting format: package, version or package,version)
        if [[ "$line" =~ ^([^,]+),(.+)$ ]]; then
            local pkg=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local ver=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -z "$pkg" ] || [ -z "$ver" ]; then
                print_warning "Skipping invalid line: $line"
                continue
            fi
            
            # Validate package name length
            if [ ${#pkg} -lt 2 ]; then
                print_warning "Skipping package '$pkg' - name too short"
                continue
            fi
            
            packages_array+=("$pkg:$ver")
            print_success "Loaded: $pkg -> $ver"
        else
            print_warning "Skipping invalid line format: $line"
        fi
    done < "$file"
    
    if [ ${#packages_array[@]} -eq 0 ]; then
        print_error "No valid package entries found in $file"
        exit 1
    fi
    
    print_success "Loaded ${#packages_array[@]} package(s) from file"
    
    # Return the array (by printing it)
    printf '%s\n' "${packages_array[@]}"
}

# Load packages based on mode
if [ -n "$PACKAGES_FILE" ]; then
    # Multi-package mode: load packages from file
    # Compatible with Bash 3.2+ (macOS default)
    PACKAGES_TO_UPDATE=()
    while IFS= read -r line; do
        PACKAGES_TO_UPDATE+=("$line")
    done < <(parse_packages_file "$PACKAGES_FILE")
else
    # Single package mode: create array with single entry
    PACKAGES_TO_UPDATE=("$PACKAGE:$TARGET_VERSION_ARG")
fi

# Get list of repositories in the organization
print_info "Fetching repositories from organization: $ORG"
REPOS=$(gh repo list "$ORG" --limit 1000 --json name -q '.[].name')

if [ -z "$REPOS" ]; then
    print_warning "No repositories found in organization $ORG."
    exit 0
fi

print_success "Found $(echo "$REPOS" | wc -l | tr -d ' ') repositories."

# Process each repository
for REPO in $REPOS; do
    print_header "Processing repository: $ORG/$REPO"
    
    # Clone the repository to the temporary directory
    print_info "Cloning repository..."
    cd "$TEMP_DIR"
    if ! gh repo clone "$ORG/$REPO" "$REPO" 2>/dev/null; then
        print_error "Failed to clone repository $ORG/$REPO. Skipping."
        continue
    fi
    
    cd "$REPO"
    
    # Determine which branch to work with based on strategy
    WORKING_BRANCH=""
    if [ "$USE_MAIN_STRATEGY" = true ]; then
        # Use main branch strategy - look for main branch
        if git ls-remote --heads origin main | grep -q main; then
            WORKING_BRANCH="main"
            print_info "Using main branch strategy. Working with branch: $WORKING_BRANCH"
        else
            print_warning "Main branch not found in $ORG/$REPO and using main strategy. Skipping repository."
            continue
        fi
    else
        # Use dev branch strategy - only work with dev branch, skip if it doesn't exist
        if git ls-remote --heads origin dev | grep -q dev; then
            WORKING_BRANCH="dev"
            print_info "Using dev branch strategy. Working with branch: $WORKING_BRANCH"
        else
            print_warning "Dev branch not found in $ORG/$REPO and using dev strategy. Skipping repository."
            continue
        fi
    fi
    
    # Checkout the working branch
    git checkout "$WORKING_BRANCH" > /dev/null 2>&1
    
    # Check if requirements.txt exists
    if [ ! -f "requirements.txt" ]; then
        print_warning "requirements.txt not found in $WORKING_BRANCH branch of $ORG/$REPO. Skipping."
        continue
    fi
    
    # Track if any changes were made in this repository
    REPO_HAS_CHANGES=false
    UPDATED_PACKAGES=()
    
    # Process each package in the list
    for PACKAGE_ENTRY in "${PACKAGES_TO_UPDATE[@]}"; do
        # Parse package name and target version
        PACKAGE=$(echo "$PACKAGE_ENTRY" | cut -d':' -f1)
        TARGET_VERSION=$(echo "$PACKAGE_ENTRY" | cut -d':' -f2)
        
        print_color "$CYAN" "---"
        print_color "$CYAN" "Checking package: $PACKAGE (target: $TARGET_VERSION)"
        
        # Check if the package exists in requirements.txt - making sure to match exact package name
        if ! grep -q "^${PACKAGE}[[:space:]]*[=]" requirements.txt; then
            print_warning "Package $PACKAGE not found in requirements.txt. Skipping this package."
            continue
        fi
        
        # Get current version of the package - use exact package matching
        CURRENT_LINE=$(grep -E "^${PACKAGE}[[:space:]]*[=]" requirements.txt)
        CURRENT_VERSION=$(echo "$CURRENT_LINE" | sed -E "s/^${PACKAGE}[[:space:]]*==?//")
        # Trim any whitespace
        CURRENT_VERSION=$(echo "$CURRENT_VERSION" | tr -d '[:space:]')
        print_info "Current version of $PACKAGE: $CURRENT_VERSION"
        
        # Check if package is already at target version
        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
            print_success "Package $PACKAGE is already at target version $TARGET_VERSION. Skipping."
            continue
        fi
        
        # Check if minimum version requirement applies (only in single package mode)
        if [ -n "$MIN_VERSION" ]; then
            # Function to compare versions (handles simple version formats)
            version_lt() {
                # Remove any characters after the version number
                local v1=$(echo "$1" | sed 's/[^0-9.].*$//')
                local v2=$(echo "$2" | sed 's/[^0-9.].*$//')
                
                # Compare versions
                if [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ] && [ "$v1" != "$v2" ]; then
                    return 0  # v1 < v2
                else
                    return 1  # v1 >= v2
                fi
            }
            
            if version_lt "$CURRENT_VERSION" "$MIN_VERSION"; then
                # Package is below minimum version - not qualified for update
                print_warning "Package $PACKAGE version $CURRENT_VERSION is below minimum version $MIN_VERSION. Not qualified for update."
                continue
            else
                print_color "$GREEN$BOLD" "Package $PACKAGE version $CURRENT_VERSION is qualified (>= $MIN_VERSION) and will be updated to $TARGET_VERSION"
            fi
        else
            print_color "$GREEN$BOLD" "Package $PACKAGE version $CURRENT_VERSION will be updated to $TARGET_VERSION"
        fi
        
        # Update the package version in requirements.txt
        print_info "Updating $PACKAGE to version $TARGET_VERSION..."
        # Use more precise sed command to replace the entire version string
        # This handles versions with wildcards, pre-release tags, etc.
        sed -i.bak -E "s/^(${PACKAGE})[[:space:]]*==?[[:space:]]*[^[:space:]]+[[:space:]]*$/\1==${TARGET_VERSION}/" requirements.txt
        rm -f requirements.txt.bak
        
        # Validate the replacement was successful
        NEW_LINE=$(grep -E "^${PACKAGE}[[:space:]]*[=]" requirements.txt)
        if ! echo "$NEW_LINE" | grep -q "^${PACKAGE}==${TARGET_VERSION}$"; then
            print_error "Failed to properly update $PACKAGE in requirements.txt"
            print_warning "Expected: ${PACKAGE}==${TARGET_VERSION}"
            print_warning "Got: $NEW_LINE"
            continue
        fi
        
        REPO_HAS_CHANGES=true
        UPDATED_PACKAGES+=("$PACKAGE:$CURRENT_VERSION->$TARGET_VERSION")
    done
    
    # If changes were made, commit and push
    if [ "$REPO_HAS_CHANGES" = true ]; then
        print_color "$CYAN" "---"
        print_color "$YELLOW" "Summary of changes in this repository:"
        for UPDATE in "${UPDATED_PACKAGES[@]}"; do
            PKG_NAME=$(echo "$UPDATE" | cut -d':' -f1)
            VERSIONS=$(echo "$UPDATE" | cut -d':' -f2)
            print_color "$YELLOW" "  • $PKG_NAME: $VERSIONS"
        done
        
        # Show diff for review
        print_color "$YELLOW" "\nFull diff:"
        git diff
        
        # Check for auto-approve or ask for confirmation
        if [ "$AUTO_APPROVE" = true ]; then
            print_info "Auto-approve mode enabled. Proceeding with changes..."
            APPROVE="y"
        else
            print_color "$YELLOW" "Approve these changes? (y/n): "
            read APPROVE
        fi
        
        if [ "$APPROVE" = "y" ] || [ "$APPROVE" = "Y" ]; then
            # Create commit message
            if [ ${#UPDATED_PACKAGES[@]} -eq 1 ]; then
                PKG_NAME=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f1)
                TARGET_VER=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f2 | cut -d'-' -f2 | cut -d'>' -f2)
                COMMIT_MSG="Update $PKG_NAME to $TARGET_VER"
            else
                COMMIT_MSG="Update multiple packages: "
                for UPDATE in "${UPDATED_PACKAGES[@]}"; do
                    PKG_NAME=$(echo "$UPDATE" | cut -d':' -f1)
                    COMMIT_MSG="$COMMIT_MSG$PKG_NAME, "
                done
                # Remove trailing comma and space
                COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/, $//')
            fi
            
            # Create a new branch for the update if using main strategy
            if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
                # Generate branch name
                if [ ${#UPDATED_PACKAGES[@]} -eq 1 ]; then
                    PKG_NAME=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f1)
                    TARGET_VER=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f2 | cut -d'-' -f2 | cut -d'>' -f2)
                    BRANCH_NAME="update-$PKG_NAME-to-$TARGET_VER"
                else
                    BRANCH_NAME="update-multiple-packages-$(date +%Y%m%d-%H%M%S)"
                fi
                
                print_info "Using main branch strategy - will create PR for manual merge..."
                git checkout -b "$BRANCH_NAME"
            else
                print_info "Using dev branch strategy - will commit directly to $WORKING_BRANCH..."
                BRANCH_NAME="$WORKING_BRANCH"
            fi
            
            # Commit changes
            git add requirements.txt
            git commit -m "$COMMIT_MSG"
            
            if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
                # For main branch strategy: push feature branch and create PR (no auto-merge)
                if git push -u origin "$BRANCH_NAME"; then
                    print_success "Changes pushed to branch $BRANCH_NAME in $ORG/$REPO."
                    
                    # Create a pull request
                    print_info "Creating pull request..."
                    PR_TITLE="$COMMIT_MSG"
                    
                    # Build PR body
                    PR_BODY="This PR updates the following packages:\n\n"
                    for UPDATE in "${UPDATED_PACKAGES[@]}"; do
                        PKG_NAME=$(echo "$UPDATE" | cut -d':' -f1)
                        VERSIONS=$(echo "$UPDATE" | cut -d':' -f2)
                        PR_BODY="${PR_BODY}- $PKG_NAME: $VERSIONS\n"
                    done
                    
                    if PR_URL=$(gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base main --head "$BRANCH_NAME"); then
                        print_pr_link "$PR_URL"
                        print_color "$PURPLE" "Note: The PR has been created for manual review and merge."
                    else
                        print_error "Failed to create pull request."
                    fi
                else
                    print_error "Failed to push changes to $ORG/$REPO."
                fi
            else
                # For dev branch strategy: push directly to the branch
                if git push origin "$WORKING_BRANCH"; then
                    print_success "Changes pushed directly to $WORKING_BRANCH branch in $ORG/$REPO."
                else
                    print_error "Failed to push changes to $ORG/$REPO."
                fi
            fi
        else
            print_warning "Changes not approved. Skipping."
        fi
    else
        print_info "No packages needed updating in this repository."
    fi
    
    print_success "Finished processing $ORG/$REPO."
done

print_header "Script completed successfully!"
