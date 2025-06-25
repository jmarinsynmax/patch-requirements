#!/bin/bash

# Script to update package versions in requirements.txt across multiple repositories
# This script uses GitHub CLI (gh) to interact with repositories

set -e

# Function to display usage information
usage() {
    echo "Usage: $0 -o <organization> -p <package> -v <minimum_version> [-m] [-y]"
    echo "  -o: GitHub organization name"
    echo "  -p: Package name to check and update"
    echo "  -v: Minimum version required"
    echo "  -m: Only update packages on the same major version"
    echo "  -y: Auto-approve all changes (skip user confirmation)"
    echo "  -h: Display this help message"
    exit 1
}

# Process command line arguments
while getopts "o:p:v:myh" opt; do
    case ${opt} in
        o)
            ORG=$OPTARG
            ;;
        p)
            PACKAGE=$OPTARG
            ;;
        v)
            MIN_VERSION=$OPTARG
            ;;
        m)
            MAJOR_VERSION_CHECK=true
            ;;
        y)
            AUTO_APPROVE=true
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." 1>&2
            usage
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$ORG" ] || [ -z "$PACKAGE" ] || [ -z "$MIN_VERSION" ]; then
    echo "Error: Missing required arguments."
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
    
    # Check if dev branch exists
    if ! git ls-remote --heads origin dev | grep -q dev; then
        echo "dev branch not found in $ORG/$REPO. Skipping."
        continue
    fi
    
    # Checkout dev branch
    git checkout dev > /dev/null 2>&1
    
    # Check if requirements.txt exists
    if [ ! -f "requirements.txt" ]; then
        echo "requirements.txt not found in dev branch of $ORG/$REPO. Skipping."
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
    
    # Function to extract major version number
    get_major_version() {
        echo "$1" | sed 's/[^0-9.].*$//' | cut -d. -f1
    }
    
    # Check if current version is less than minimum version
    if version_lt "$CURRENT_VERSION" "$MIN_VERSION"; then
        echo "Current version $CURRENT_VERSION is less than minimum required version $MIN_VERSION."
        
        # Check major version compatibility if -m flag is set
        if [ "$MAJOR_VERSION_CHECK" = true ]; then
            CURRENT_MAJOR=$(get_major_version "$CURRENT_VERSION")
            MIN_MAJOR=$(get_major_version "$MIN_VERSION")
            
            if [ "$CURRENT_MAJOR" != "$MIN_MAJOR" ]; then
                echo "Major version mismatch: current major version is $CURRENT_MAJOR, minimum required major version is $MIN_MAJOR."
                echo "Skipping update due to -m flag (major version check enabled)."
                continue
            else
                echo "Major version check passed: both versions are on major version $CURRENT_MAJOR."
            fi
        fi
        
        # Create a new branch for the update
        BRANCH_NAME="dev-update-$PACKAGE-to-$MIN_VERSION"
        git checkout -b "$BRANCH_NAME"
        
        # Update the package version in requirements.txt
        echo "Updating $PACKAGE to version $MIN_VERSION..."
        # Use more precise sed command with word boundaries to ensure exact package name matching
        sed -i.bak -E "s/^(${PACKAGE})[[:space:]]*==?[[:space:]]*[0-9][0-9.]*/${PACKAGE}==${MIN_VERSION}/" requirements.txt
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
            # Commit and push changes
            git add requirements.txt
            git commit -m "Update $PACKAGE to $MIN_VERSION to fix vulnerability"
            
            if git push -u origin "$BRANCH_NAME"; then
                echo "Changes pushed to branch $BRANCH_NAME in $ORG/$REPO."
                
                # Create a pull request
                echo "Creating pull request..."
                PR_TITLE="Update $PACKAGE to $MIN_VERSION"
                PR_BODY="This PR updates $PACKAGE from $CURRENT_VERSION to $MIN_VERSION to fix a security vulnerability."
                
                if PR_URL=$(gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base dev --head "$BRANCH_NAME"); then
                    echo "Pull request created: $PR_URL"
                else
                    echo "Failed to create pull request."
                fi
            else
                echo "Failed to push changes to $ORG/$REPO."
            fi
        else
            echo "Changes not approved. Skipping."
        fi
    else
        echo "Package $PACKAGE already meets or exceeds minimum version requirement ($MIN_VERSION). Skipping."
    fi
    
    echo "Finished processing $ORG/$REPO."
done

echo "======================================================="
echo "Script completed successfully!"
