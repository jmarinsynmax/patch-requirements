#!/bin/bash

# Script to update package versions in requirements.txt across multiple repositories
# This script uses GitHub CLI (gh) to interact with repositories

set -e

# Function to display usage information
usage() {
    echo "Usage: $0 -o <organization> -p <package> -r <target_version> [-v <minimum_version>] [-y] [--main]"
    echo "  -o: GitHub organization name"
    echo "  -p: Package name to check and update"
    echo "  -r: Target version to update packages to (mandatory)"
    echo "  -v: Minimum version required for qualification (optional, if not set all packages qualify)"
    echo "  -y: Auto-approve all changes (skip user confirmation)"
    echo "  --main: Use main branch strategy (create PR for manual merge). Default is dev branch strategy"
    echo "  -h: Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -o myorg -p requests -r 2.28.0                    # Update all packages to 2.28.0"
    echo "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0          # Update packages >= 11.2.0 to 11.3.0"
    echo "  $0 -o myorg -p requests -r 11.3.0 -v 11.2.0 --main   # Same but use main branch strategy"
    echo ""
    echo "Note: If -v is specified, only packages >= minimum version will be updated."
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
    echo "Error: Missing required arguments."
    echo "Required: -o (organization), -p (package), -r (target version)"
    usage
fi

# Check if package name is reasonable (to avoid partial matches)
if [ ${#PACKAGE} -lt 2 ]; then
    echo "Error: Package name '$PACKAGE' is too short and might cause incorrect matches."
    echo "Please provide a more specific package name."
    exit 1
fi

# Check if gh is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed. Please install it first."
    echo "Visit https://cli.github.com/ for installation instructions."
    exit 1
fi

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated. Please run 'gh auth login' first."
    exit 1
fi

# Create a temporary directory for repository operations
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Cleanup function to remove temporary directory on exit
cleanup() {
    echo "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

# Register cleanup function to run on exit
trap cleanup EXIT

# Get list of repositories in the organization
echo "Fetching repositories from organization: $ORG"
REPOS=$(gh repo list "$ORG" --limit 1000 --json name -q '.[].name')

if [ -z "$REPOS" ]; then
    echo "No repositories found in organization $ORG."
    exit 0
fi

echo "Found $(echo "$REPOS" | wc -l | tr -d ' ') repositories."

# Process each repository
for REPO in $REPOS; do
    echo "======================================================="
    echo "Processing repository: $ORG/$REPO"
    
    # Clone the repository to the temporary directory
    echo "Cloning repository..."
    cd "$TEMP_DIR"
    if ! gh repo clone "$ORG/$REPO" "$REPO" 2>/dev/null; then
        echo "Error: Failed to clone repository $ORG/$REPO. Skipping."
        continue
    fi
    
    cd "$REPO"
    
    # Determine which branch to work with based on strategy
    WORKING_BRANCH=""
    if [ "$USE_MAIN_STRATEGY" = true ]; then
        # Use main branch strategy - look for main branch
        if git ls-remote --heads origin main | grep -q main; then
            WORKING_BRANCH="main"
            echo "Using main branch strategy. Working with branch: $WORKING_BRANCH"
        else
            echo "Main branch not found in $ORG/$REPO and using main strategy. Skipping repository."
            continue
        fi
    else
        # Use dev branch strategy - only work with dev branch, skip if it doesn't exist
        if git ls-remote --heads origin dev | grep -q dev; then
            WORKING_BRANCH="dev"
            echo "Using dev branch strategy. Working with branch: $WORKING_BRANCH"
        else
            echo "Dev branch not found in $ORG/$REPO and using dev strategy. Skipping repository."
            continue
        fi
    fi
    
    # Checkout the working branch
    git checkout "$WORKING_BRANCH" > /dev/null 2>&1
    
    # Check if requirements.txt exists
    if [ ! -f "requirements.txt" ]; then
        echo "requirements.txt not found in $WORKING_BRANCH branch of $ORG/$REPO. Skipping."
        continue
    fi
    
    # Check if the package exists in requirements.txt - making sure to match exact package name
    if ! grep -q "^${PACKAGE}[[:space:]]*[=]" requirements.txt; then
        echo "Package $PACKAGE not found in requirements.txt. Skipping."
        continue
    fi
    
    # Get current version of the package - use exact package matching
    CURRENT_LINE=$(grep -E "^${PACKAGE}[[:space:]]*[=]" requirements.txt)
    CURRENT_VERSION=$(echo "$CURRENT_LINE" | sed -E "s/^${PACKAGE}[[:space:]]*==?//")
    # Trim any whitespace
    CURRENT_VERSION=$(echo "$CURRENT_VERSION" | tr -d '[:space:]')
    echo "Current version of $PACKAGE: $CURRENT_VERSION"
    
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
        echo "Package $PACKAGE is already at target version $TARGET_VERSION. Skipping."
    elif [ -n "$MIN_VERSION" ]; then
        # Minimum version is specified - check qualification
        if version_lt "$CURRENT_VERSION" "$MIN_VERSION"; then
            # Package is below minimum version - not qualified for update
            NEEDS_UPDATE=false
            echo "Package $PACKAGE version $CURRENT_VERSION is below minimum version $MIN_VERSION. Not qualified for update."
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
        echo "$UPDATE_REASON."
        
        # Create a new branch for the update
        BRANCH_NAME="update-$PACKAGE-to-$TARGET_VERSION"
        
        # Handle different branch strategies
        if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
            echo "Using main branch strategy - will create PR for manual merge..."
            # Create a feature branch from main
            git checkout -b "$BRANCH_NAME"
        else
            echo "Using dev branch strategy - will commit directly to $WORKING_BRANCH..."
            # For dev strategy, commit directly to the current branch (no new branch needed)
            BRANCH_NAME="$WORKING_BRANCH"
        fi
        
        # Update the package version in requirements.txt
        echo "Updating $PACKAGE to version $TARGET_VERSION..."
        # Use more precise sed command with word boundaries to ensure exact package name matching
        sed -i.bak -E "s/^(${PACKAGE})[[:space:]]*==?[[:space:]]*[0-9][0-9.]*/${PACKAGE}==${TARGET_VERSION}/" requirements.txt
        rm -f requirements.txt.bak
        
        # Show diff for review
        echo "Changes to be made:"
        git diff
        
        # Check for auto-approve or ask for confirmation
        if [ "$AUTO_APPROVE" = true ]; then
            echo "Auto-approve mode enabled. Proceeding with changes..."
            APPROVE="y"
        else
            read -p "Approve these changes? (y/n): " APPROVE
        fi
        
        if [ "$APPROVE" = "y" ] || [ "$APPROVE" = "Y" ]; then
            # Commit changes
            git add requirements.txt
            git commit -m "Update $PACKAGE to $TARGET_VERSION to fix vulnerability"
            
            if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
                # For main branch strategy: push feature branch and create PR (no auto-merge)
                if git push -u origin "$BRANCH_NAME"; then
                    echo "Changes pushed to branch $BRANCH_NAME in $ORG/$REPO."
                    
                    # Create a pull request
                    echo "Creating pull request..."
                    PR_TITLE="Update $PACKAGE to $TARGET_VERSION"
                    if [ -n "$MIN_VERSION" ]; then
                        PR_BODY="This PR updates $PACKAGE from $CURRENT_VERSION to $TARGET_VERSION (qualified package >= $MIN_VERSION) to fix a security vulnerability."
                    else
                        PR_BODY="This PR updates $PACKAGE from $CURRENT_VERSION to $TARGET_VERSION to fix a security vulnerability."
                    fi
                    
                    if PR_URL=$(gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base main --head "$BRANCH_NAME"); then
                        echo "Pull request created: $PR_URL"
                        echo "Note: The PR has been created for manual review and merge."
                    else
                        echo "Failed to create pull request."
                    fi
                else
                    echo "Failed to push changes to $ORG/$REPO."
                fi
            else
                # For dev branch strategy: push directly to the branch
                if git push origin "$WORKING_BRANCH"; then
                    echo "Changes pushed directly to $WORKING_BRANCH branch in $ORG/$REPO."
                else
                    echo "Failed to push changes to $ORG/$REPO."
                fi
            fi
        else
            echo "Changes not approved. Skipping."
        fi
    fi
    
    echo "Finished processing $ORG/$REPO."
done

echo "======================================================="
echo "Script completed successfully!"
