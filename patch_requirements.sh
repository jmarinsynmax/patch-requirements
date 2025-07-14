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
    print_color "$WHITE$BOLD" "Usage: $0 -o <organization> -p <package> -r <target_version> [-v <minimum_version>] [-y] [--main]"
    echo
    print_color "$YELLOW" "Required Arguments:"
    print_color "$WHITE" "  -o: GitHub organization name"
    print_color "$WHITE" "  -p: Package name to check and update"
    print_color "$WHITE" "  -r: Target version to update packages to"
    echo
    print_color "$YELLOW" "Optional Arguments:"
    print_color "$WHITE" "  -v: Minimum version required for qualification (if not set, all packages qualify)"
    print_color "$WHITE" "  -y: Auto-approve all changes (skip user confirmation)"
    print_color "$WHITE" "  --main: Use main branch strategy (create PR for manual merge). Default is dev branch strategy"
    print_color "$WHITE" "  -h: Display this help message"
    echo
    print_color "$CYAN" "Examples:"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 2.28.0                    # Update all packages to 2.28.0"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0          # Update packages >= 11.2.0 to 11.3.0"
    print_color "$WHITE" "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0 --main   # Same but use main branch strategy"
    echo
    print_color "$YELLOW" "Note: If -v is specified, only packages >= minimum version will be updated."
    exit 1
}

# Initialize variables
USE_MAIN_STRATEGY=false
TARGET_VERSION_ARG=""
MIN_VERSION=""

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
if [ -z "$ORG" ] || [ -z "$PACKAGE" ] || [ -z "$TARGET_VERSION_ARG" ]; then
    print_error "Missing required arguments."
    print_warning "Required: -o (organization), -p (package), -r (target version)"
    usage
fi

# Check if package name is reasonable (to avoid partial matches)
if [ ${#PACKAGE} -lt 2 ]; then
    print_error "Package name '$PACKAGE' is too short and might cause incorrect matches."
    print_warning "Please provide a more specific package name."
    exit 1
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
    
    # Check if the package exists in requirements.txt - making sure to match exact package name
    if ! grep -q "^${PACKAGE}[[:space:]]*[=]" requirements.txt; then
        print_warning "Package $PACKAGE not found in requirements.txt. Skipping."
        continue
    fi
    
    # Get current version of the package - use exact package matching
    CURRENT_LINE=$(grep -E "^${PACKAGE}[[:space:]]*[=]" requirements.txt)
    CURRENT_VERSION=$(echo "$CURRENT_LINE" | sed -E "s/^${PACKAGE}[[:space:]]*==?//")
    # Trim any whitespace
    CURRENT_VERSION=$(echo "$CURRENT_VERSION" | tr -d '[:space:]')
    print_info "Current version of $PACKAGE: $CURRENT_VERSION"
    
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
    
    # Function to compare versions (greater than)
    version_gt() {
        # Remove any characters after the version number
        local v1=$(echo "$1" | sed 's/[^0-9.].*$//')
        local v2=$(echo "$2" | sed 's/[^0-9.].*$//')
        
        # Compare versions
        if [ "$(printf '%s\n' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ] && [ "$v1" != "$v2" ]; then
            return 0  # v1 > v2
        else
            return 1  # v1 <= v2
        fi
    }
    
    # Check if current version needs to be updated
    NEEDS_UPDATE=false
    UPDATE_REASON=""
    TARGET_VERSION="$TARGET_VERSION_ARG"
    
    # First check if package is already at target version
    if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
        NEEDS_UPDATE=false
        print_success "Package $PACKAGE is already at target version $TARGET_VERSION. Skipping."
    elif [ -n "$MIN_VERSION" ]; then
        # Minimum version is specified - check qualification
        if version_lt "$CURRENT_VERSION" "$MIN_VERSION"; then
            # Package is below minimum version - not qualified for update
            NEEDS_UPDATE=false
            print_warning "Package $PACKAGE version $CURRENT_VERSION is below minimum version $MIN_VERSION. Not qualified for update."
        else
            # Package meets minimum version requirement
            NEEDS_UPDATE=true
            UPDATE_REASON="Package $PACKAGE version $CURRENT_VERSION is qualified (>= $MIN_VERSION) and will be updated to $TARGET_VERSION"
        fi
    else
        # No minimum version specified - all packages qualify (except those already at target)
        NEEDS_UPDATE=true
        UPDATE_REASON="Package $PACKAGE version $CURRENT_VERSION will be updated to $TARGET_VERSION (no minimum version restriction)"
    fi
    
    if [ "$NEEDS_UPDATE" = true ]; then
        print_color "$GREEN$BOLD" "$UPDATE_REASON."
        
        # Create a new branch for the update
        BRANCH_NAME="update-$PACKAGE-to-$TARGET_VERSION"
        
        # Handle different branch strategies
        if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
            print_info "Using main branch strategy - will create PR for manual merge..."
            # Create a feature branch from main
            git checkout -b "$BRANCH_NAME"
        else
            print_info "Using dev branch strategy - will commit directly to $WORKING_BRANCH..."
            # For dev strategy, commit directly to the current branch (no new branch needed)
            BRANCH_NAME="$WORKING_BRANCH"
        fi
        
        # Update the package version in requirements.txt
        print_info "Updating $PACKAGE to version $TARGET_VERSION..."
        # Use more precise sed command with word boundaries to ensure exact package name matching
        sed -i.bak -E "s/^(${PACKAGE})[[:space:]]*==?[[:space:]]*[0-9][0-9.]*/${PACKAGE}==${TARGET_VERSION}/" requirements.txt
        rm -f requirements.txt.bak
        
        # Show diff for review
        print_color "$YELLOW" "Changes to be made:"
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
            # Commit changes
            git add requirements.txt
            git commit -m "Update $PACKAGE to $TARGET_VERSION to fix vulnerability"
            
            if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
                # For main branch strategy: push feature branch and create PR (no auto-merge)
                if git push -u origin "$BRANCH_NAME"; then
                    print_success "Changes pushed to branch $BRANCH_NAME in $ORG/$REPO."
                    
                    # Create a pull request
                    print_info "Creating pull request..."
                    PR_TITLE="Update $PACKAGE to $TARGET_VERSION"
                    if [ -n "$MIN_VERSION" ]; then
                        PR_BODY="This PR updates $PACKAGE from $CURRENT_VERSION to $TARGET_VERSION (qualified package >= $MIN_VERSION) to fix a security vulnerability."
                    else
                        PR_BODY="This PR updates $PACKAGE from $CURRENT_VERSION to $TARGET_VERSION to fix a security vulnerability."
                    fi
                    
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
    fi
    
    print_success "Finished processing $ORG/$REPO."
done

print_header "Script completed successfully!"
