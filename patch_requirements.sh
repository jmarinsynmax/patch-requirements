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
    print_color "$WHITE" "      Format: package_name, target_version[, minimum_version]"
    print_color "$WHITE" "      Example file contents:"
    print_color "$WHITE" "        fastapi, 0.120.4, 0.115.0"
    print_color "$WHITE" "        starlette, 0.49.1"
    print_color "$WHITE" "      Note: minimum_version is optional. If specified, only packages"
    print_color "$WHITE" "            with version >= minimum_version will be updated."
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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed. Please install it first."
    print_info "On macOS: brew install jq"
    exit 1
fi

# Check if gh is authenticated
if ! gh auth status &> /dev/null; then
    print_error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
    exit 1
fi

# Function to parse packages file and return array of package,version pairs
parse_packages_file() {
    local file=$1
    declare -a packages_array
    
    print_info "Parsing packages file: $file" >&2
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # Parse package and version (expecting format: package, target_version or package, target_version, minimum_version)
        if [[ "$line" =~ ^([^,]+),([^,]+)(,(.+))?$ ]]; then
            local pkg=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local ver=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local min_ver=$(echo "${BASH_REMATCH[4]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [ -z "$pkg" ] || [ -z "$ver" ]; then
                print_warning "Skipping invalid line: $line" >&2
                continue
            fi
            
            # Validate package name length
            if [ ${#pkg} -lt 2 ]; then
                print_warning "Skipping package '$pkg' - name too short" >&2
                continue
            fi
            
            # Format: package:target_version:minimum_version (minimum_version can be empty)
            packages_array+=("$pkg:$ver:$min_ver")
            if [ -n "$min_ver" ]; then
                print_success "Loaded: $pkg -> $ver (min: $min_ver)" >&2
            else
                print_success "Loaded: $pkg -> $ver" >&2
            fi
        else
            print_warning "Skipping invalid line format: $line" >&2
        fi
    done < "$file"
    
    if [ ${#packages_array[@]} -eq 0 ]; then
        print_error "No valid package entries found in $file" >&2
        exit 1
    fi
    
    print_success "Loaded ${#packages_array[@]} package(s) from file" >&2
    
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
    # Format: package:target_version:minimum_version
    PACKAGES_TO_UPDATE=("$PACKAGE:$TARGET_VERSION_ARG:$MIN_VERSION")
fi

# Load skip list if skip.txt exists
SKIP_REPOS=()
if [ -f "skip.txt" ]; then
    print_info "Loading repository skip list from skip.txt..."
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        SKIP_REPOS+=("$line")
        print_color "$YELLOW" "  → Will skip: $line"
    done < "skip.txt"
    
    if [ ${#SKIP_REPOS[@]} -gt 0 ]; then
        print_success "Loaded ${#SKIP_REPOS[@]} repository/repositories to skip"
    fi
else
    print_info "No skip.txt file found. All repositories will be processed."
fi

# Get list of repositories in the organization
print_info "Fetching repositories from organization: $ORG"
REPOS=$(gh repo list "$ORG" --limit 1000 --json name -q '.[].name')

if [ -z "$REPOS" ]; then
    print_warning "No repositories found in organization $ORG."
    exit 0
fi

print_success "Found $(echo "$REPOS" | wc -l | tr -d ' ') repositories."

# Determine which branch to check based on strategy
WORKING_BRANCH=""
if [ "$USE_MAIN_STRATEGY" = true ]; then
    WORKING_BRANCH="main"
else
    WORKING_BRANCH="dev"
fi

# ── Parallel pre-fetch phase ──────────────────────────────────────────────
# Fetch requirements.txt for all non-skipped repos in parallel using xargs
# for true sliding-window concurrency (no batch-wait problem).
PREFETCH_DIR=$(mktemp -d)
MAX_PARALLEL=30

prefetch_cleanup() {
    rm -rf "$PREFETCH_DIR"
}
trap prefetch_cleanup EXIT

# Build list of repos to fetch (exclude skip list)
REPOS_TO_FETCH=()
for REPO in $REPOS; do
    SHOULD_SKIP=false
    for SKIP_REPO in "${SKIP_REPOS[@]}"; do
        if [ "$REPO" = "$SKIP_REPO" ]; then
            SHOULD_SKIP=true
            break
        fi
    done
    if [ "$SHOULD_SKIP" = false ]; then
        REPOS_TO_FETCH+=("$REPO")
    fi
done

print_info "Pre-fetching requirements.txt from $WORKING_BRANCH branch for ${#REPOS_TO_FETCH[@]} repositories (parallel=$MAX_PARALLEL)..."

# Helper script for xargs: fetches requirements.txt for one repo
_FETCH_SCRIPT=$(cat << 'FETCHEOF'
REPO="$1"; ORG="$2"; BRANCH="$3"; OUTDIR="$4"; MAIN_STRATEGY="$5"
FILE_JSON=$(gh api "repos/$ORG/$REPO/contents/requirements.txt?ref=$BRANCH" 2>/dev/null) || true
if [ -n "$FILE_JSON" ]; then
    printf '%s' "$FILE_JSON" > "$OUTDIR/${REPO}.json"
fi
if [ "$MAIN_STRATEGY" = "true" ]; then
    DEV_JSON=$(gh api "repos/$ORG/$REPO/contents/requirements.txt?ref=dev" 2>/dev/null) || true
    if [ -n "$DEV_JSON" ]; then
        printf '%s' "$DEV_JSON" > "$OUTDIR/${REPO}.dev.json"
    fi
fi
FETCHEOF
)

# Run pre-fetch with xargs -P for true sliding-window parallelism
printf '%s\n' "${REPOS_TO_FETCH[@]}" | xargs -P "$MAX_PARALLEL" -I{} bash -c "$_FETCH_SCRIPT" _ {} "$ORG" "$WORKING_BRANCH" "$PREFETCH_DIR" "$USE_MAIN_STRATEGY"

FETCHED_COUNT=$(ls -1 "$PREFETCH_DIR"/*.json 2>/dev/null | grep -cv '\.dev\.json$' 2>/dev/null || echo "0")
print_success "Pre-fetch complete. ${FETCHED_COUNT} repositories have requirements.txt on $WORKING_BRANCH."

# Process each repository
for REPO in $REPOS; do
    print_header "Processing repository: $ORG/$REPO"
    
    # Check if repository is in skip list
    SHOULD_SKIP=false
    for SKIP_REPO in "${SKIP_REPOS[@]}"; do
        if [ "$REPO" = "$SKIP_REPO" ]; then
            SHOULD_SKIP=true
            break
        fi
    done
    
    if [ "$SHOULD_SKIP" = true ]; then
        print_warning "Repository $REPO is in skip list. Skipping."
        continue
    fi
    
    # Use pre-fetched data instead of making API calls
    if [ ! -f "$PREFETCH_DIR/${REPO}.json" ]; then
        print_warning "$WORKING_BRANCH branch or requirements.txt not found in $ORG/$REPO. Skipping repository."
        continue
    fi
    
    FILE_JSON=$(cat "$PREFETCH_DIR/${REPO}.json")
    REQUIREMENTS_CONTENT=$(echo "$FILE_JSON" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null)
    FILE_SHA=$(echo "$FILE_JSON" | jq -r '.sha // empty' 2>/dev/null)
    
    if [ -z "$REQUIREMENTS_CONTENT" ] || [ -z "$FILE_SHA" ]; then
        print_error "Failed to parse requirements.txt content or SHA. Skipping repository."
        continue
    fi
    
    print_success "requirements.txt loaded from $WORKING_BRANCH branch."
    
    # If using main strategy, load pre-fetched dev branch requirements.txt
    if [ "$USE_MAIN_STRATEGY" = true ]; then
        if [ ! -f "$PREFETCH_DIR/${REPO}.dev.json" ]; then
            print_warning "dev branch or requirements.txt not found in $ORG/$REPO. Skipping repository."
            continue
        fi
        
        DEV_FILE_JSON=$(cat "$PREFETCH_DIR/${REPO}.dev.json")
        DEV_REQUIREMENTS_CONTENT=$(echo "$DEV_FILE_JSON" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null)
        
        if [ -z "$DEV_REQUIREMENTS_CONTENT" ]; then
            print_error "Failed to fetch dev branch requirements.txt content. Skipping repository."
            continue
        fi
        
        print_success "Dev branch requirements.txt loaded successfully."
    fi
    
    # Scan requirements.txt for packages that need updating
    print_info "Scanning requirements.txt for packages that need updating..."
    
    # Track which packages need updating
    PACKAGES_NEED_UPDATE=false
    PACKAGES_TO_UPDATE_IN_REPO=()
    
    # Check each package to see if it needs updating
    for PACKAGE_ENTRY in "${PACKAGES_TO_UPDATE[@]}"; do
        # Parse package name, target version, and optional minimum version
        IFS=':' read -r PACKAGE TARGET_VERSION PACKAGE_MIN_VERSION <<< "$PACKAGE_ENTRY"
        
        print_color "$CYAN" "  → Checking package: $PACKAGE (target: $TARGET_VERSION)"
        
        # Check if the package exists in requirements.txt - case-insensitive matching
        if ! echo "$REQUIREMENTS_CONTENT" | grep -iq "^${PACKAGE}[[:space:]]*[=]"; then
            print_warning "    Package $PACKAGE not found in requirements.txt. Skipping this package."
            continue
        fi
        
        # If using main strategy, verify this specific package is at target version in dev
        if [ "$USE_MAIN_STRATEGY" = true ]; then
            if echo "$DEV_REQUIREMENTS_CONTENT" | grep -iq "^${PACKAGE}[[:space:]]*[=]"; then
                DEV_VERSION=$(echo "$DEV_REQUIREMENTS_CONTENT" | grep -iE "^${PACKAGE}[[:space:]]*[=]" | sed -E "s/^${PACKAGE}[[:space:]]*==?//i" | tr -d '[:space:]')
                
                if [ "$DEV_VERSION" != "$TARGET_VERSION" ]; then
                    print_warning "    Package $PACKAGE in dev branch is at version $DEV_VERSION, not target $TARGET_VERSION. Skipping this package."
                    continue
                fi
                print_success "    Verified $PACKAGE at target version in dev branch."
            else
                print_warning "    Package $PACKAGE not found in dev branch. Skipping this package."
                continue
            fi
        fi
        
        # Get current version of the package - case-insensitive matching
        CURRENT_LINE=$(echo "$REQUIREMENTS_CONTENT" | grep -iE "^${PACKAGE}[[:space:]]*[=]")
        # Extract version, stripping any inline comments first
        CURRENT_VERSION=$(echo "$CURRENT_LINE" | sed -E "s/#.*$//" | sed -E "s/^${PACKAGE}[[:space:]]*==?//i")
        # Trim any whitespace
        CURRENT_VERSION=$(echo "$CURRENT_VERSION" | tr -d '[:space:]')
        print_info "    Current version: $CURRENT_VERSION"
        
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
        
        # Check if package is already at target version
        if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
            print_success "    Already at target version. Skipping."
            continue
        fi
        
        # Prevent downgrade: check if current version is higher than target version
        if ! version_lt "$CURRENT_VERSION" "$TARGET_VERSION"; then
            print_warning "    Current version ($CURRENT_VERSION) is higher than or equal to target ($TARGET_VERSION). Skipping to prevent downgrade."
            continue
        fi
        
        # Check if minimum version requirement applies
        if [ -n "$PACKAGE_MIN_VERSION" ]; then
            if version_lt "$CURRENT_VERSION" "$PACKAGE_MIN_VERSION"; then
                # Package is below minimum version - not qualified for update
                print_warning "    Version $CURRENT_VERSION is below minimum $PACKAGE_MIN_VERSION. Not qualified."
                continue
            else
                print_color "$GREEN" "    ✓ Qualified (>= $PACKAGE_MIN_VERSION). Will upgrade to $TARGET_VERSION"
            fi
        else
            print_color "$GREEN" "    ✓ Will upgrade from $CURRENT_VERSION to $TARGET_VERSION"
        fi
        
        PACKAGES_NEED_UPDATE=true
        PACKAGES_TO_UPDATE_IN_REPO+=("$PACKAGE:$CURRENT_VERSION:$TARGET_VERSION")
    done
    
    # Skip if no packages need updating
    if [ "$PACKAGES_NEED_UPDATE" = false ]; then
        print_info "No packages need updating in this repository. Skipping."
        continue
    fi
    
    print_success "Found ${#PACKAGES_TO_UPDATE_IN_REPO[@]} package(s) that need updating."
    
    # Write current content to a temp file for sed operations (no repo clone needed)
    TEMP_REQ=$(mktemp)
    printf '%s\n' "$REQUIREMENTS_CONTENT" > "$TEMP_REQ"
    
    # Track if any changes were made in this repository
    REPO_HAS_CHANGES=false
    UPDATED_PACKAGES=()
    
    # Process each package that needs updating
    for PACKAGE_INFO in "${PACKAGES_TO_UPDATE_IN_REPO[@]}"; do
        # Parse package info
        PACKAGE=$(echo "$PACKAGE_INFO" | cut -d':' -f1)
        CURRENT_VERSION=$(echo "$PACKAGE_INFO" | cut -d':' -f2)
        TARGET_VERSION=$(echo "$PACKAGE_INFO" | cut -d':' -f3)
        
        print_color "$CYAN" "---"
        print_color "$CYAN" "Updating package: $PACKAGE ($CURRENT_VERSION → $TARGET_VERSION)"
        
        # Update the package version in the temp file
        print_info "Updating $PACKAGE to version $TARGET_VERSION..."
        # Use case-insensitive sed command to handle different capitalizations
        # This handles versions with wildcards, pre-release tags, and preserves inline comments
        sed -i.bak -E "s/^(${PACKAGE})[[:space:]]*==?[[:space:]]*[^[:space:]#]+([[:space:]]*(#.*)?)?$/\1==${TARGET_VERSION}\2/i" "$TEMP_REQ"
        rm -f "${TEMP_REQ}.bak"
        
        # Validate the replacement was successful - case-insensitive check (allow inline comments)
        NEW_LINE=$(grep -iE "^${PACKAGE}[[:space:]]*[=]" "$TEMP_REQ")
        if ! echo "$NEW_LINE" | grep -iqE "^${PACKAGE}==${TARGET_VERSION}([[:space:]]*(#.*)?)?$"; then
            print_error "Failed to properly update $PACKAGE in requirements.txt"
            print_warning "Expected: ${PACKAGE}==${TARGET_VERSION} (with optional comment)"
            print_warning "Got: $NEW_LINE"
            continue
        fi
        
        REPO_HAS_CHANGES=true
        UPDATED_PACKAGES+=("$PACKAGE:$CURRENT_VERSION->$TARGET_VERSION")
    done
    
    # Read the updated content and clean up temp file
    UPDATED_CONTENT=$(cat "$TEMP_REQ")
    rm -f "$TEMP_REQ"
    
    # If changes were made, push via GitHub Contents API
    if [ "$REPO_HAS_CHANGES" = true ]; then
        print_color "$CYAN" "---"
        print_color "$YELLOW" "Summary of changes in this repository:"
        for UPDATE in "${UPDATED_PACKAGES[@]}"; do
            PKG_NAME=$(echo "$UPDATE" | cut -d':' -f1)
            VERSIONS=$(echo "$UPDATE" | cut -d':' -f2)
            print_color "$YELLOW" "  • $PKG_NAME: $VERSIONS"
        done
        
        # Show diff for review (unified diff of old vs new content)
        print_color "$YELLOW" "\nChanges to be applied:"
        diff -u --label "current" --label "updated" <(echo "$REQUIREMENTS_CONTENT") <(echo "$UPDATED_CONTENT") || true
        echo
        
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
            
            # Base64 encode the updated content for the GitHub Contents API
            ENCODED_CONTENT=$(printf '%s\n' "$UPDATED_CONTENT" | base64 | tr -d '\n')
            
            if [ "$USE_MAIN_STRATEGY" = true ] && [ "$WORKING_BRANCH" = "main" ]; then
                # Main branch strategy: create feature branch, update file via API, create PR
                
                # Generate branch name
                if [ ${#UPDATED_PACKAGES[@]} -eq 1 ]; then
                    PKG_NAME=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f1)
                    TARGET_VER=$(echo "${UPDATED_PACKAGES[0]}" | cut -d':' -f2 | cut -d'-' -f2 | cut -d'>' -f2)
                    BRANCH_NAME="update-$PKG_NAME-to-$TARGET_VER"
                else
                    BRANCH_NAME="update-multiple-packages"
                fi
                
                # Get main branch commit SHA to create the feature branch from
                MAIN_SHA=$(gh api "repos/$ORG/$REPO/git/ref/heads/main" --jq '.object.sha' 2>/dev/null) || true
                if [ -z "$MAIN_SHA" ]; then
                    print_error "Failed to get main branch SHA. Skipping repository."
                    continue
                fi
                
                # Create feature branch from main via Refs API
                print_info "Creating branch $BRANCH_NAME from main..."
                CREATE_EXIT=0
                CREATE_RESPONSE=$(gh api "repos/$ORG/$REPO/git/refs" \
                    -X POST \
                    -f "ref=refs/heads/$BRANCH_NAME" \
                    -f "sha=$MAIN_SHA" 2>&1) || CREATE_EXIT=$?
                
                if [ $CREATE_EXIT -ne 0 ]; then
                    if echo "$CREATE_RESPONSE" | grep -q "Reference already exists"; then
                        print_warning "Branch $BRANCH_NAME already exists. Attempting to reuse..."
                    else
                        print_error "Failed to create branch $BRANCH_NAME: $CREATE_RESPONSE"
                        continue
                    fi
                fi
                
                # Update requirements.txt on the feature branch via Contents API
                print_info "Updating requirements.txt on branch $BRANCH_NAME via API..."
                UPDATE_EXIT=0
                UPDATE_RESPONSE=$(gh api "repos/$ORG/$REPO/contents/requirements.txt" \
                    -X PUT \
                    -f "message=$COMMIT_MSG" \
                    -f "content=$ENCODED_CONTENT" \
                    -f "sha=$FILE_SHA" \
                    -f "branch=$BRANCH_NAME" 2>&1) || UPDATE_EXIT=$?
                
                if [ $UPDATE_EXIT -ne 0 ]; then
                    if echo "$UPDATE_RESPONSE" | grep -q "409\|does not match"; then
                        print_error "Conflict: requirements.txt was modified since we read it. Skipping repository."
                    else
                        print_error "Failed to update file via API: $UPDATE_RESPONSE"
                    fi
                    continue
                fi
                
                print_success "File updated on branch $BRANCH_NAME in $ORG/$REPO."
                
                # Create a pull request
                print_info "Creating pull request..."
                PR_TITLE="$COMMIT_MSG"
                
                # Build PR body
                PR_BODY="This PR updates the following packages:"$'\n\n'
                for UPDATE in "${UPDATED_PACKAGES[@]}"; do
                    PKG_NAME=$(echo "$UPDATE" | cut -d':' -f1)
                    VERSIONS=$(echo "$UPDATE" | cut -d':' -f2)
                    PR_BODY="${PR_BODY}- $PKG_NAME: $VERSIONS"$'\n'
                done
                
                if PR_URL=$(gh pr create -R "$ORG/$REPO" --title "$PR_TITLE" --body "$PR_BODY" --base main --head "$BRANCH_NAME"); then
                    print_pr_link "$PR_URL"
                    
                    # Ask user if they want to merge the PR (or auto-merge if -y flag is set)
                    MERGE_PR="n"
                    if [ "$AUTO_APPROVE" = true ]; then
                        print_info "Auto-approve mode enabled. Merging PR automatically..."
                        MERGE_PR="y"
                    else
                        print_color "$YELLOW" "Do you want to merge this PR now? (y/n): "
                        read MERGE_PR
                    fi
                    
                    if [ "$MERGE_PR" = "y" ] || [ "$MERGE_PR" = "Y" ]; then
                        print_info "Merging pull request..."
                        if gh pr merge "$PR_URL" --merge --delete-branch --admin; then
                            print_success "PR merged successfully and branch deleted."
                        else
                            print_error "Failed to merge pull request. You may need to merge it manually."
                        fi
                    else
                        print_color "$PURPLE" "Note: The PR has been created for manual review and merge."
                    fi
                else
                    print_error "Failed to create pull request."
                fi
            else
                # Dev branch strategy: update file directly via Contents API
                print_info "Updating requirements.txt directly on $WORKING_BRANCH via API..."
                
                UPDATE_EXIT=0
                UPDATE_RESPONSE=$(gh api "repos/$ORG/$REPO/contents/requirements.txt" \
                    -X PUT \
                    -f "message=$COMMIT_MSG" \
                    -f "content=$ENCODED_CONTENT" \
                    -f "sha=$FILE_SHA" \
                    -f "branch=$WORKING_BRANCH" 2>&1) || UPDATE_EXIT=$?
                
                if [ $UPDATE_EXIT -ne 0 ]; then
                    if echo "$UPDATE_RESPONSE" | grep -q "409\|does not match"; then
                        print_error "Conflict: requirements.txt was modified since we read it. Skipping repository."
                    else
                        print_error "Failed to update file via API: $UPDATE_RESPONSE"
                    fi
                    continue
                fi
                
                print_success "Changes pushed directly to $WORKING_BRANCH branch in $ORG/$REPO."
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
