#!/bin/bash

# Script to disable specific Cloud Run services by setting manual scaling to 0
# Usage: ./disable_cloud_run_services.sh <PROJECT_ID>

set -e

# Check if project ID is provided
if [ -z "$1" ]; then
    echo "Error: Project ID is required"
    echo "Usage: ./disable_cloud_run_services.sh <PROJECT_ID>"
    exit 1
fi

PROJECT_ID="$1"

# List of Cloud Run services to disable
SERVICES=(
    "int-voyage-profiling"
    "int-ship-tracking"
    "int-stream-scrape"
    "int-ship-name-id"
    "enr-opt-seg-ship-length"
    "int-intel-logs"
    "int-ship-clusters"
    "enr-future-path-prediction-v2"
    "export-ais-events-management"
    "int-stats-dashboard"
    "luxspace-ingest"
    "int-mmsi-sharers"
    "spf-detection"
    "int-make-ship"
    "spire-vessels-scrape"
    "alert-endpoint"
    "optical-spoofing"
    "smr-run-smoother"
    "order-planet-composite"
    "ais-classify-erratic-updates-management"
    "enr-trigger"
    "vessel-risk-assessments"
    "enr-atr-pipeline-test"
    "resubmission"
    "sanctions-qc-tool-v1"
    "spoofing-footprint-v2"
    "ing-osint-scrape"
    "export-alert"
    "export-alert-management"
    "export-bucket"
    "ais-db-maintanance"
    "enr-sen1-management"
    "ing-sen1-search"
    "ais-world-of-ports-scrape"
    "ais-ownership-ingest"
    "spire-spoofing-ingest"
    "api-search-update"
    "ais-spoofing-ingest"
    "ais-classify-erratic-updates"
    "ais-split-mmsi-sharers"
    "ais-identify-erratic-updates"
    "spire-messages-scrape"
)

# Default region (can be modified or made into a parameter)
REGION="us-central1"

echo "Starting to disable Cloud Run services in project: $PROJECT_ID"
echo "Region: $REGION"
echo "Total services to disable: ${#SERVICES[@]}"
echo ""

# Counter for tracking progress
SUCCESSFUL=0
FAILED=0
SKIPPED=0

# Loop through each service and set scaling to 0
for SERVICE in "${SERVICES[@]}"; do
    echo "Processing service: $SERVICE"
    
    # Check if service exists
    if gcloud run services describe "$SERVICE" --project="$PROJECT_ID" --region="$REGION" --format="value(name)" &>/dev/null; then
        # Set manual scaling to 0 to disable the service
        if gcloud run services update "$SERVICE" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --scaling=0 2>&1; then
            echo "✓ Successfully disabled: $SERVICE"
            ((SUCCESSFUL++))
        else
            echo "✗ Failed to disable: $SERVICE"
            ((FAILED++))
        fi
    else
        echo "⚠ Service not found (skipping): $SERVICE"
        ((SKIPPED++))
    fi
    echo ""
done

echo "================================================"
echo "Summary:"
echo "  Successfully disabled: $SUCCESSFUL"
echo "  Failed: $FAILED"
echo "  Skipped (not found): $SKIPPED"
echo "  Total: ${#SERVICES[@]}"
echo "================================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
