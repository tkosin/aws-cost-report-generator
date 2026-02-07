#!/bin/bash

# AWS Cost Report Generator
# Generates an interactive HTML report of AWS costs by service
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - Valid AWS credentials in ~/.aws/credentials or environment variables
#   - Python 3 with json module
#
# Usage: 
#   ./generate_aws_cost_report.sh [YYYY-MM] [OPTIONS]
#
# Arguments:
#   YYYY-MM   Month to report (default: current month)
#
# Options:
#   --profile PROFILE          AWS profile to use (default: default)
#   --profiles PROFILE1,PROFILE2  Multiple AWS profiles (comma-separated)
#   --help                     Show this help message
#
# Examples:
#   ./generate_aws_cost_report.sh                              # Current month, interactive profile selection
#   ./generate_aws_cost_report.sh 2026-01                     # January 2026
#   ./generate_aws_cost_report.sh 2026-01 --profile yodkosin  # Single profile
#   ./generate_aws_cost_report.sh --profiles yodkosin,production,dev  # Multiple profiles
#   AWS_PROFILE=prod ./generate_aws_cost_report.sh            # Using environment variable
#
# AWS Credentials:
#   Script uses standard AWS credential chain:
#   1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   2. AWS_PROFILE environment variable
#   3. ~/.aws/credentials (default profile)
#   4. IAM role (if running on EC2/ECS)

set -e

# Help function
show_help() {
    head -n 35 "$0" | grep '^#' | sed 's/^# //g' | sed 's/^#//g'
    exit 0
}

# Parse command line arguments
AWS_PROFILES=()
MONTH_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --profile|--profiles)
            # Support comma-separated profiles
            IFS=',' read -ra PROFILES_ARG <<< "$2"
            for prof in "${PROFILES_ARG[@]}"; do
                AWS_PROFILES+=("$prof")
            done
            shift 2
            ;;
        *)
            if [[ -z "$MONTH_ARG" ]]; then
                MONTH_ARG="$1"
            fi
            shift
            ;;
    esac
done

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI is not installed"
    echo "   Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is not installed"
    exit 1
fi

# If profiles not specified, check if user has multiple profiles and ask
if [[ ${#AWS_PROFILES[@]} -eq 0 ]] && [[ -z "$AWS_DEFAULT_PROFILE" ]]; then
    if [[ -f ~/.aws/credentials ]]; then
        # Get list of profiles from credentials file
        AVAILABLE_PROFILES=($(grep -E '^\[.*\]$' ~/.aws/credentials | tr -d '[]'))

        if [[ ${#AVAILABLE_PROFILES[@]} -gt 1 ]]; then
            echo "🔍 Found AWS profiles in ~/.aws/credentials"
            echo ""
            echo "   Select profiles (comma-separated numbers, e.g., 1,3,4)"
            echo ""

            # Display profiles with numbers
            for i in "${!AVAILABLE_PROFILES[@]}"; do
                echo "  $((i+1))) ${AVAILABLE_PROFILES[$i]}"
            done
            echo ""

            # Get user selection
            while true; do
                read -r -p "❓ Select profiles (1-${#AVAILABLE_PROFILES[@]}) or press Enter for default [1]: " selection

                # Default to 1 if empty
                if [[ -z "$selection" ]]; then
                    selection="1"
                fi

                # Parse comma-separated selections
                IFS=',' read -ra SELECTIONS <<< "$selection"
                VALID=true
                TEMP_PROFILES=()

                for sel in "${SELECTIONS[@]}"; do
                    # Trim whitespace
                    sel=$(echo "$sel" | xargs)

                    # Validate each selection
                    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le ${#AVAILABLE_PROFILES[@]} ]]; then
                        TEMP_PROFILES+=("${AVAILABLE_PROFILES[$((sel-1))]}")
                    else
                        VALID=false
                        echo "❌ Invalid selection: $sel"
                        break
                    fi
                done

                if [[ "$VALID" == true ]] && [[ ${#TEMP_PROFILES[@]} -gt 0 ]]; then
                    AWS_PROFILES=("${TEMP_PROFILES[@]}")
                    echo "✅ Using profile(s): ${AWS_PROFILES[*]}"
                    echo ""
                    break
                else
                    echo "❌ Invalid selection. Please enter comma-separated numbers between 1 and ${#AVAILABLE_PROFILES[@]}."
                fi
            done
        elif [[ ${#AVAILABLE_PROFILES[@]} -eq 1 ]]; then
            AWS_PROFILES=("${AVAILABLE_PROFILES[0]}")
            echo "🔍 Found single AWS profile: ${AWS_PROFILES[0]}"
            echo ""
        fi
    fi
fi

# If still no profiles, use default
if [[ ${#AWS_PROFILES[@]} -eq 0 ]]; then
    AWS_PROFILES=("default")
fi

# Validate AWS credentials for each profile
echo "🔐 Validating AWS credentials for selected profiles..."
echo ""

# Use indexed arrays instead of associative arrays (bash 3.2 compatible)
PROFILE_IDENTITIES=()
PROFILE_ACCOUNT_IDS=()
PROFILE_USER_IDS=()

for profile in "${AWS_PROFILES[@]}"; do
    echo "   Checking profile: $profile"

    # Set profile for this check
    export AWS_PROFILE="$profile"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "   ❌ Error: AWS credentials not configured or invalid for profile: $profile"
        echo ""
        echo "   Configure credentials:"
        echo "   1. Run: aws configure --profile $profile"
        echo "   2. Or set environment variables"
        echo ""
        exit 1
    fi

    # Get identity info
    IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    USER_ID=$(aws sts get-caller-identity --query 'UserId' --output text)

    PROFILE_IDENTITIES+=("$IDENTITY")
    PROFILE_ACCOUNT_IDS+=("$ACCOUNT_ID")
    PROFILE_USER_IDS+=("$USER_ID")

    echo "   ✅ $profile: $IDENTITY"
done

echo ""

# Determine the month to report
if [ -z "$MONTH_ARG" ]; then
    YEAR_MONTH=$(date +%Y-%m)
else
    YEAR_MONTH=$MONTH_ARG
fi

YEAR=$(echo $YEAR_MONTH | cut -d'-' -f1)
MONTH=$(echo $YEAR_MONTH | cut -d'-' -f2)
MONTH_NAME=$(date -j -f "%Y-%m" "$YEAR_MONTH" +"%B %Y" 2>/dev/null || echo "$YEAR_MONTH")

# Calculate date range for MTD (Month-to-Date)
START_DATE_MTD="${YEAR_MONTH}-01"
# Get last day of month
LAST_DAY=$(date -j -v1d -v+1m -v-1d -f "%Y-%m-%d" "$START_DATE_MTD" +%d 2>/dev/null || echo "31")
END_DATE_MTD="${YEAR_MONTH}-${LAST_DAY}"

# Calculate date range for YTD (Year-to-Date)
START_DATE_YTD="${YEAR}-01-01"
END_DATE_YTD="${YEAR_MONTH}-${LAST_DAY}"

echo "📊 Generating AWS Cost Report for $MONTH_NAME"
echo "   MTD range: $START_DATE_MTD to $END_DATE_MTD"
echo "   YTD range: $START_DATE_YTD to $END_DATE_YTD"
echo ""

# Fetch cost data for each profile
declare -a TEMP_FILES_MTD
declare -a TEMP_FILES_YTD

for profile in "${AWS_PROFILES[@]}"; do
    echo "🔄 Fetching cost data for profile: $profile"

    export AWS_PROFILE="$profile"

    # Fetch MTD cost data
    TEMP_FILE_MTD="/tmp/aws_costs_mtd_${YEAR_MONTH}_${profile}.json"
    echo "   Fetching MTD data..."

    aws ce get-cost-and-usage \
        --time-period Start=$START_DATE_MTD,End=$END_DATE_MTD \
        --granularity DAILY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "$TEMP_FILE_MTD"

    if [ ! -s "$TEMP_FILE_MTD" ]; then
        echo "   ❌ Error: Failed to fetch MTD AWS cost data for profile: $profile"
        exit 1
    fi

    TEMP_FILES_MTD+=("$TEMP_FILE_MTD")
    echo "   ✅ MTD data fetched"

    # Fetch YTD cost data
    TEMP_FILE_YTD="/tmp/aws_costs_ytd_${YEAR_MONTH}_${profile}.json"
    echo "   Fetching YTD data..."

    aws ce get-cost-and-usage \
        --time-period Start=$START_DATE_YTD,End=$END_DATE_YTD \
        --granularity DAILY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --output json > "$TEMP_FILE_YTD"

    if [ ! -s "$TEMP_FILE_YTD" ]; then
        echo "   ❌ Error: Failed to fetch YTD AWS cost data for profile: $profile"
        exit 1
    fi

    TEMP_FILES_YTD+=("$TEMP_FILE_YTD")
    echo "   ✅ YTD data fetched"
    echo ""
done

echo "✅ All cost data fetched successfully"

# Generate HTML report
# Create filename with profiles
PROFILES_STR=$(IFS='+'; echo "${AWS_PROFILES[*]}")
ACCOUNT_IDS_STR=$(IFS='+'; echo "${PROFILE_ACCOUNT_IDS[*]}")

OUTPUT_FILE="$HOME/aws_cost_report_${YEAR_MONTH}_${PROFILES_STR}_${ACCOUNT_IDS_STR}.html"
echo "📝 Generating HTML report..."

# Export profile metadata as environment variables for Python
for i in "${!AWS_PROFILES[@]}"; do
    profile="${AWS_PROFILES[$i]}"
    # Replace hyphens and dots with underscores for valid env var names
    safe_profile=$(echo "$profile" | sed 's/[-.]/_/g')
    export "PROFILE_IDENTITY_${safe_profile}=${PROFILE_IDENTITIES[$i]}"
    export "PROFILE_ACCOUNT_ID_${safe_profile}=${PROFILE_ACCOUNT_IDS[$i]}"
done

# Pass data to Python via heredoc
PROFILES_JSON=$(printf '%s\n' "${AWS_PROFILES[@]}" | jq -R . | jq -s .)
TEMP_FILES_MTD_JSON=$(printf '%s\n' "${TEMP_FILES_MTD[@]}" | jq -R . | jq -s .)
TEMP_FILES_YTD_JSON=$(printf '%s\n' "${TEMP_FILES_YTD[@]}" | jq -R . | jq -s .)

python3 << EOF
import json
from datetime import datetime
import os

# Parse profiles and file paths from environment/arguments
profiles = ${PROFILES_JSON}
temp_files_mtd = ${TEMP_FILES_MTD_JSON}
temp_files_ytd = ${TEMP_FILES_YTD_JSON}

# Load profile metadata
profile_identities = {}
profile_account_ids = {}

for profile in profiles:
    # Replace hyphens and dots with single underscores to match env var names (same as bash sed)
    safe_profile = profile.replace('-', '_').replace('.', '_')
    profile_identities[profile] = os.environ.get(f'PROFILE_IDENTITY_{safe_profile}', '')
    profile_account_ids[profile] = os.environ.get(f'PROFILE_ACCOUNT_ID_{safe_profile}', '')

# Storage for all profile data
all_profiles_data_mtd = {}
all_profiles_data_ytd = {}

# Load and process data for each profile
for idx, profile in enumerate(profiles):
    # Load MTD data
    with open(temp_files_mtd[idx], 'r') as f:
        data_mtd = json.load(f)

    # Load YTD data
    with open(temp_files_ytd[idx], 'r') as f:
        data_ytd = json.load(f)

    # Process MTD data for this profile
    services_mtd = {}
    dates_mtd = []

    for day in data_mtd['ResultsByTime']:
        date = day['TimePeriod']['Start']
        if date not in dates_mtd:
            dates_mtd.append(date)

        for group in day['Groups']:
            service = group['Keys'][0]
            cost = float(group['Metrics']['UnblendedCost']['Amount'])

            if service not in services_mtd:
                services_mtd[service] = {}
            services_mtd[service][date] = cost

    all_profiles_data_mtd[profile] = {
        'services': services_mtd,
        'dates': dates_mtd
    }

    # Process YTD data for this profile
    services_ytd = {}
    dates_ytd = []

    for day in data_ytd['ResultsByTime']:
        date = day['TimePeriod']['Start']
        if date not in dates_ytd:
            dates_ytd.append(date)

        for group in day['Groups']:
            service = group['Keys'][0]
            cost = float(group['Metrics']['UnblendedCost']['Amount'])

            if service not in services_ytd:
                services_ytd[service] = {}
            services_ytd[service][date] = cost

    all_profiles_data_ytd[profile] = {
        'services': services_ytd,
        'dates': dates_ytd
    }

# Use dates from first profile (they should be the same)
dates_mtd = all_profiles_data_mtd[profiles[0]]['dates']
dates_ytd = all_profiles_data_ytd[profiles[0]]['dates']

# Create combined data (sum across all profiles)
services_mtd_combined = {}
services_ytd_combined = {}

for profile in profiles:
    for service, costs in all_profiles_data_mtd[profile]['services'].items():
        if service not in services_mtd_combined:
            services_mtd_combined[service] = {}
        for date, cost in costs.items():
            services_mtd_combined[service][date] = services_mtd_combined[service].get(date, 0) + cost

for profile in profiles:
    for service, costs in all_profiles_data_ytd[profile]['services'].items():
        if service not in services_ytd_combined:
            services_ytd_combined[service] = {}
        for date, cost in costs.items():
            services_ytd_combined[service][date] = services_ytd_combined[service].get(date, 0) + cost

# For backward compatibility, set default data to combined
services_mtd = services_mtd_combined
services_ytd = services_ytd_combined

# Prepare data for each profile and combined
profile_data_output = {}

# Process combined data
def process_profile_data(services_mtd, services_ytd, dates_mtd, dates_ytd, profile_name):
    # Filter MTD services
    filtered_services_mtd = {svc: costs for svc, costs in services_mtd.items() if sum(costs.values()) > 0}

    # Filter YTD services
    filtered_services_ytd = {svc: costs for svc, costs in services_ytd.items() if sum(costs.values()) > 0}

    # Sort services
    sorted_services_mtd = sorted(filtered_services_mtd.items(), key=lambda x: sum(x[1].values()), reverse=True)
    sorted_services_ytd = sorted(filtered_services_ytd.items(), key=lambda x: sum(x[1].values()), reverse=True)

    # Calculate daily totals for MTD
    daily_totals_mtd = {}
    for date in dates_mtd:
        daily_totals_mtd[date] = sum(services_mtd.get(svc, {}).get(date, 0) for svc in filtered_services_mtd)

    # Calculate daily totals for YTD
    daily_totals_ytd = {}
    for date in dates_ytd:
        daily_totals_ytd[date] = sum(services_ytd.get(svc, {}).get(date, 0) for svc in filtered_services_ytd)

    return {
        'services_mtd': services_mtd,
        'services_ytd': services_ytd,
        'filtered_services_mtd': filtered_services_mtd,
        'filtered_services_ytd': filtered_services_ytd,
        'sorted_services_mtd': sorted_services_mtd,
        'sorted_services_ytd': sorted_services_ytd,
        'daily_totals_mtd': daily_totals_mtd,
        'daily_totals_ytd': daily_totals_ytd,
        'dates_mtd': dates_mtd,
        'dates_ytd': dates_ytd
    }

# Process combined data
profile_data_output['combined'] = process_profile_data(
    services_mtd_combined, services_ytd_combined, dates_mtd, dates_ytd, 'combined'
)

# Process individual profile data
for profile in profiles:
    profile_data_output[profile] = process_profile_data(
        all_profiles_data_mtd[profile]['services'],
        all_profiles_data_ytd[profile]['services'],
        all_profiles_data_mtd[profile]['dates'],
        all_profiles_data_ytd[profile]['dates'],
        profile
    )

# Use combined as default for rendering
current_data = profile_data_output['combined']
services_mtd = current_data['services_mtd']
services_ytd = current_data['services_ytd']
filtered_services_mtd = current_data['filtered_services_mtd']
filtered_services_ytd = current_data['filtered_services_ytd']
sorted_services_mtd = current_data['sorted_services_mtd']
sorted_services_ytd = current_data['sorted_services_ytd']
daily_totals_mtd = current_data['daily_totals_mtd']
daily_totals_ytd = current_data['daily_totals_ytd']

# Use MTD as default
services = services_mtd
filtered_services = filtered_services_mtd
sorted_services = sorted_services_mtd
dates = dates_mtd
daily_totals = daily_totals_mtd

# Determine weekends
def is_weekend(date_str):
    dt = datetime.strptime(date_str, '%Y-%m-%d')
    return dt.weekday() >= 5  # 5=Saturday, 6=Sunday

# Prepare data for HTML
html_content = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Cost Report - $MONTH_NAME</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Open+Sans:wght@400;600;700&display=swap');

        body {
            font-family: 'Amazon Ember', 'Open Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: #eaeded;
            color: #16191f;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 2px;
            box-shadow: 0 1px 1px 0 rgba(0,28,36,0.3), 1px 1px 1px 0 rgba(0,28,36,0.15), -1px 1px 1px 0 rgba(0,28,36,0.15);
        }
        h1 {
            color: #232F3E;
            margin-bottom: 10px;
            font-weight: 700;
            font-size: 28px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 16px;
            margin: 20px 0 40px 0;
        }
        .summary-card {
            background: white;
            border: 2px solid #FF9900;
            color: #232F3E;
            padding: 20px;
            border-radius: 2px;
            box-shadow: 0 1px 1px rgba(0,28,36,0.1);
        }
        .summary-card h3 {
            margin: 0 0 8px 0;
            font-size: 14px;
            font-weight: 600;
            color: #545b64;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .summary-card p {
            margin: 0;
            font-size: 32px;
            font-weight: 700;
            color: #FF9900;
        }
        .summary-card .forecast {
            font-size: 14px;
            color: #545b64;
            margin-top: 8px;
            font-weight: 400;
        }
        .summary-card .forecast.warning {
            color: #d13212;
            font-weight: 600;
        }
        .chart-container {
            margin: 40px 0;
            height: 500px;
            background: white;
            padding: 20px;
            border-radius: 2px;
            border: 1px solid #d5dbdb;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 30px;
            font-size: 13px;
        }
        th, td {
            padding: 12px 10px;
            text-align: right;
            border-bottom: 1px solid #d5dbdb;
        }
        th:first-child, td:first-child {
            text-align: left;
            position: sticky;
            left: 0;
            background: white;
            font-weight: 600;
            max-width: 300px;
        }
        th {
            background: #fafafa;
            font-weight: 700;
            position: sticky;
            top: 0;
            z-index: 10;
            color: #232F3E;
            text-transform: uppercase;
            font-size: 12px;
            letter-spacing: 0.5px;
            border-bottom: 2px solid #FF9900;
        }
        th.weekend {
            background: #e7f6fd;
            color: #0972d3;
        }
        td.weekend {
            background: #f1f9fe;
        }
        tbody tr:hover td:not(:first-child) {
            background: #fff8e6;
        }
        tbody tr:hover td.weekend {
            background: #e7f6fd;
        }
        tbody tr:hover td:first-child {
            background: #fafafa;
        }
        .total-row {
            font-weight: bold;
            border-top: 2px solid #FF9900;
        }
        .total-row td:first-child {
            background: #232F3E !important;
            color: white;
        }
        .total-row td {
            background: #232F3E;
            color: white;
            font-weight: 700;
        }
        .total-row td.weekend {
            background: #16191f !important;
        }
        .table-wrapper {
            overflow-x: auto;
            margin-top: 20px;
            border: 1px solid #d5dbdb;
            border-radius: 2px;
        }
        .cost-high { color: #d13212; font-weight: 700; }
        .cost-medium { color: #ec7211; font-weight: 600; }
        .cost-low { color: #037f0c; }
        .aws-info {
            background: #f9f9f9;
            padding: 20px;
            border-radius: 2px;
            margin: 20px 0;
            font-size: 14px;
            border-left: 4px solid #FF9900;
            border: 1px solid #d5dbdb;
        }
        .aws-info h3 {
            margin: 0 0 15px 0;
            font-size: 16px;
            color: #232F3E;
            font-weight: 700;
        }
        .aws-info .info-row {
            display: flex;
            margin: 8px 0;
        }
        .aws-info .info-label {
            font-weight: 600;
            color: #545b64;
            min-width: 140px;
        }
        .aws-info .info-value {
            color: #16191f;
            font-family: 'Courier New', Monaco, monospace;
            word-break: break-all;
        }
        .header-row {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 20px;
        }
        .header-left {
            flex: 1;
        }
        .toggle-container {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .profile-tabs {
            display: inline-flex;
            background: white;
            border: 2px solid #d5dbdb;
            border-radius: 2px;
            padding: 2px;
        }
        .profile-tab {
            padding: 8px 16px;
            border: none;
            background: transparent;
            cursor: pointer;
            font-size: 13px;
            font-weight: 600;
            color: #545b64;
            border-radius: 0;
            transition: all 0.15s ease;
            white-space: nowrap;
        }
        .profile-tab.active {
            background: #0972d3;
            color: white;
        }
        .profile-tab:hover:not(.active) {
            background: #fafafa;
            color: #232F3E;
        }
        .toggle-switch {
            display: inline-flex;
            background: white;
            border: 2px solid #d5dbdb;
            border-radius: 2px;
            padding: 2px;
        }
        .toggle-option {
            padding: 8px 20px;
            border: none;
            background: transparent;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            color: #545b64;
            border-radius: 0;
            transition: all 0.15s ease;
        }
        .toggle-option.active {
            background: #FF9900;
            color: white;
        }
        .toggle-option:hover:not(.active) {
            background: #fafafa;
            color: #232F3E;
        }
        .hidden {
            display: none;
        }
        h2 {
            color: #232F3E;
            font-size: 20px;
            font-weight: 700;
            margin-top: 50px;
        }
        .export-btn {
            background: #0972d3;
            color: white;
            border: none;
            padding: 10px 20px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            border-radius: 2px;
            transition: background 0.15s ease;
            margin-left: 12px;
        }
        .export-btn:hover {
            background: #0860b0;
        }
        .anomaly {
            background: #fdf2f2 !important;
            border: 2px solid #d13212 !important;
            font-weight: 700 !important;
        }
        .anomaly-indicator {
            color: #d13212;
            font-size: 10px;
            vertical-align: super;
        }
        .percentage {
            font-size: 11px;
            color: #687078;
            font-weight: 400;
            display: block;
            margin-top: 2px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-row">
            <div class="header-left">
                <h1 style="margin: 0;">AWS Cost Report</h1>
                <p style="color: #545b64; margin: 8px 0 0 0; font-size: 16px; font-weight: 600;" id="subtitle">$MONTH_NAME • Month-to-Date Analysis</p>
                <p style="color: #687078; margin: 4px 0 0 0; font-size: 14px;" id="dateRange">$START_DATE_MTD to $END_DATE_MTD</p>
            </div>
            <div class="toggle-container">'''

# Add profile tabs if multiple profiles
if len(profiles) > 1:
    html_content += '''
                <div class="profile-tabs">
                    <button class="profile-tab active" id="profileBtn_combined" onclick="switchProfile('combined')">Combined</button>'''
    for profile in profiles:
        html_content += f'''
                    <button class="profile-tab" id="profileBtn_{profile}" onclick="switchProfile('{profile}')">{profile}</button>'''
    html_content += '''
                </div>'''

html_content += '''
                <div class="toggle-switch">
                    <button class="toggle-option active" id="mtdBtn" onclick="toggleView('mtd')">MTD</button>
                    <button class="toggle-option" id="ytdBtn" onclick="toggleView('ytd')">YTD</button>
                </div>
                <button class="export-btn" onclick="exportToCSV()">📥 Export CSV</button>
            </div>
        </div>

        <div class="aws-info" id="awsInfo">
            <h3>🔐 AWS Account Information</h3>
            <div id="awsInfoContent">
                <!-- Will be populated by JavaScript -->
            </div>
        </div>
        
        <div class="summary" id="summary">
            <div class="summary-card">
                <h3>Total Cost</h3>
                <p id="totalCost">\$''' + f"{sum(sum(costs.values()) for _, costs in sorted_services):.2f}" + '''</p>
                <div class="forecast" id="forecastText"></div>
            </div>
            <div class="summary-card" style="border-color: #0972d3;">
                <h3>Top Service</h3>
                <p style="color: #0972d3;" id="topService">\$''' + f"{sum(sorted_services[0][1].values()):.2f}" + '''</p>
                <div class="percentage" id="topServicePct">''' + f"{sum(sorted_services[0][1].values()) / sum(sum(costs.values()) for _, costs in sorted_services) * 100:.1f}% of total" + '''</div>
            </div>
            <div class="summary-card" style="border-color: #037f0c;">
                <h3>Avg Daily Cost</h3>
                <p style="color: #037f0c;" id="avgDaily">\$''' + f"{sum(daily_totals.values()) / len(dates):.2f}" + '''</p>
            </div>
            <div class="summary-card" style="border-color: #232F3E;">
                <h3>Services</h3>
                <p style="color: #232F3E;" id="servicesCount">''' + str(len(sorted_services)) + '''</p>
            </div>
        </div>

        <div class="chart-container">
            <canvas id="dailyCostChart"></canvas>
        </div>

        <h2 style="margin-top: 50px;">All AWS Services - Daily Breakdown</h2>
        <div class="table-wrapper">
            <table>
                <thead>
'''

# Add date headers with 2 rows: month names (weekly) and dates
# Group dates by month with monthly totals
from collections import OrderedDict
months_data = OrderedDict()
for date in dates:
    year_month = date[:7]  # YYYY-MM
    month_name = datetime.strptime(date, '%Y-%m-%d').strftime('%b %Y')  # e.g., "Jan 2026"
    if year_month not in months_data:
        months_data[year_month] = {'name': month_name, 'dates': [], 'total_costs': {}}
    months_data[year_month]['dates'].append(date)

# Calculate monthly totals for each service
for year_month in months_data:
    month_dates = months_data[year_month]['dates']
    for service, costs in services.items():
        month_total = sum(costs.get(d, 0) for d in month_dates)
        if service not in months_data[year_month]['total_costs']:
            months_data[year_month]['total_costs'][service] = month_total

# Create header: Add month name every week
html_content += '                    <tr>\\n'
html_content += '                        <th rowspan="2" style="background: #fafafa; vertical-align: middle;">Service</th>\\n'
for year_month, month_info in months_data.items():
    month_dates = month_info['dates']
    month_name = month_info['name']

    # Show month name every 7 days
    for i, date in enumerate(month_dates):
        if i % 7 == 0:
            remaining_days = min(7, len(month_dates) - i)
            html_content += f'                        <th colspan="{remaining_days}" style="background: #232F3E; color: #FF9900; border-bottom: 1px solid #FF9900; font-size: 11px;">{month_name}</th>\\n'

    # Add month total column
    html_content += f'                        <th rowspan="2" style="background: #FF9900; color: white; vertical-align: middle; font-size: 11px;">{month_name.split()[0]}<br/>Total</th>\\n'

html_content += '                        <th rowspan="2" style="background: #232F3E; color: white; vertical-align: middle;">Grand<br/>Total</th>\\n'
html_content += '                    </tr>\\n'
html_content += '                    <tr>\\n'

# Add date row (day numbers)
for year_month, month_info in months_data.items():
    for date in month_info['dates']:
        weekend_class = ' class="weekend"' if is_weekend(date) else ''
        day_only = date[8:]  # Get just the day (DD)
        html_content += f'                        <th{weekend_class} style="font-size: 11px;">{day_only}</th>\\n'

html_content += '''                    </tr>
                </thead>
                <tbody>
'''

# Add ALL service rows with weekend styling and month totals
for service, costs in sorted_services:
    total = sum(costs.values())
    html_content += f'                    <tr>\\n'
    html_content += f'                        <td title="{service}">{service[:70]}</td>\\n'

    # Add daily costs grouped by month with month totals
    for year_month, month_info in months_data.items():
        month_dates = month_info['dates']
        month_total = months_data[year_month]['total_costs'].get(service, 0)

        # Daily costs for this month
        for date in month_dates:
            cost = costs.get(date, 0)
            cost_class = 'cost-high' if cost > 50 else ('cost-medium' if cost > 10 else 'cost-low')
            cost_str = f'{cost:.2f}' if cost > 0 else '-'
            weekend_class = ' weekend' if is_weekend(date) else ''
            html_content += f'                        <td class="{cost_class}{weekend_class}">{cost_str}</td>\\n'

        # Month total cell
        html_content += f'                        <td style="font-weight: bold; background: #fff8e6; color: #232F3E; border-left: 2px solid #FF9900;">\${month_total:.2f}</td>\\n'

    # Grand total cell
    html_content += f'                        <td style="font-weight: bold; background: #fafafa; color: #232F3E; border-left: 2px solid #232F3E;">\${total:.2f}</td>\\n'
    html_content += f'                    </tr>\\n'

# Add total row with weekend styling and month totals
html_content += '                    <tr class="total-row">\\n'
html_content += '                        <td>TOTAL</td>\\n'

# Add daily totals grouped by month with month totals
for year_month, month_info in months_data.items():
    month_dates = month_info['dates']
    month_total = sum(daily_totals.get(d, 0) for d in month_dates)

    # Daily totals for this month
    for date in month_dates:
        weekend_class = ' weekend' if is_weekend(date) else ''
        html_content += f'                        <td class="{weekend_class}">\${daily_totals[date]:.2f}</td>\\n'

    # Month total cell
    html_content += f'                        <td style="background: #FF9900; color: white; font-weight: 700; border-left: 2px solid white;">\${month_total:.2f}</td>\\n'

# Grand total cell
html_content += f'                        <td style="background: #232F3E; color: white; font-weight: 700; border-left: 2px solid white;">\${sum(daily_totals.values()):.2f}</td>\\n'
html_content += '                    </tr>\\n'

html_content += '''                </tbody>
            </table>
        </div>
    </div>

    <script>
        // Helper function to check if date is weekend
        function isWeekend(dateStr) {
            const date = new Date(dateStr);
            const day = date.getDay();
            return day === 0 || day === 6; // Sunday = 0, Saturday = 6
        }

        // Calculate forecast for end of month (linear regression)
        function calculateForecast(dates, dailyTotals) {
            if (!dates || dates.length < 2) return null;

            // Get current month's last day
            const firstDate = new Date(dates[0]);
            const year = firstDate.getFullYear();
            const month = firstDate.getMonth();
            const lastDayOfMonth = new Date(year, month + 1, 0).getDate();
            const currentDay = dates.length;

            // Calculate average daily cost
            const totalCost = Object.values(dailyTotals).reduce((sum, cost) => sum + cost, 0);
            const avgDaily = totalCost / dates.length;

            // Simple linear projection
            const forecastTotal = avgDaily * lastDayOfMonth;
            const remainingDays = lastDayOfMonth - currentDay;
            const remainingCost = avgDaily * remainingDays;

            return {
                forecastTotal: forecastTotal,
                remainingCost: remainingCost,
                currentDay: currentDay,
                lastDay: lastDayOfMonth,
                avgDaily: avgDaily
            };
        }

        // Detect cost anomalies (days with unusual costs)
        function detectAnomalies(dailyTotals, threshold = 2.0) {
            const costs = Object.values(dailyTotals);
            if (costs.length < 3) return new Set();

            // Calculate mean and standard deviation
            const mean = costs.reduce((sum, cost) => sum + cost, 0) / costs.length;
            const variance = costs.reduce((sum, cost) => sum + Math.pow(cost - mean, 2), 0) / costs.length;
            const stdDev = Math.sqrt(variance);

            // Find anomalies (values beyond threshold standard deviations)
            const anomalies = new Set();
            Object.entries(dailyTotals).forEach(([date, cost]) => {
                if (Math.abs(cost - mean) > threshold * stdDev && cost > mean) {
                    anomalies.add(date);
                }
            });

            return anomalies;
        }

        // Export data to CSV
        function exportToCSV() {
            const profileData = allProfilesData[currentProfile];
            const viewData = profileData[currentView];
            const dates = viewData.dates;
            const allServices = viewData.allServices;
            const dailyTotals = viewData.dailyTotals;

            // Create CSV header
            let csv = 'Service,' + dates.join(',') + ',Total' + String.fromCharCode(10);

            // Add service rows
            allServices.forEach(service => {
                const row = [service.name];
                dates.forEach(date => {
                    row.push((service.costs[date] || 0).toFixed(2));
                });
                row.push(service.total.toFixed(2));
                csv += row.join(',') + String.fromCharCode(10);
            });

            // Add total row
            const totalRow = ['TOTAL'];
            dates.forEach(date => {
                totalRow.push((dailyTotals[date] || 0).toFixed(2));
            });
            const grandTotal = Object.values(dailyTotals).reduce((sum, cost) => sum + cost, 0);
            totalRow.push(grandTotal.toFixed(2));
            csv += totalRow.join(',') + String.fromCharCode(10);

            // Download CSV
            const blob = new Blob([csv], { type: 'text/csv' });
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'aws_cost_report_' + currentProfile + '_' + currentView + '_' + dates[0].substring(0, 7) + '.csv';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);
        }

        // Profiles configuration
        const profiles = ''' + json.dumps(profiles) + ''';

        // Profile metadata
        const profileMetadata = {};
'''

# Add profile metadata for each profile
for profile in profiles:
    safe_profile = profile.replace('-', '_').replace('.', '_')
    identity = profile_identities.get(profile, '')
    account_id = profile_account_ids.get(profile, '')
    html_content += f'''
        profileMetadata[{json.dumps(profile)}] = {{
            identity: {json.dumps(identity)},
            account_id: {json.dumps(account_id)}
        }};
'''

html_content += '''
        // Profile data - prepare JavaScript data structure
        const allProfilesData = {};
'''

# Export all profile data to JavaScript
for profile_key in ['combined'] + profiles:
    if profile_key in profile_data_output:
        pdata = profile_data_output[profile_key]

        # Prepare data for JSON serialization
        mtd_top_services = [
            {
                'label': service[:40],
                'data': [costs.get(d, 0) for d in pdata['dates_mtd']],
            }
            for service, costs in pdata['sorted_services_mtd'][:10]
        ]

        mtd_all_services = [
            {
                'name': service,
                'costs': {d: costs.get(d, 0) for d in pdata['dates_mtd']},
                'total': sum(costs.values())
            }
            for service, costs in pdata['sorted_services_mtd']
        ]

        ytd_top_services = [
            {
                'label': service[:40],
                'data': [costs.get(d, 0) for d in pdata['dates_ytd']],
            }
            for service, costs in pdata['sorted_services_ytd'][:10]
        ]

        ytd_all_services = [
            {
                'name': service,
                'costs': {d: costs.get(d, 0) for d in pdata['dates_ytd']},
                'total': sum(costs.values())
            }
            for service, costs in pdata['sorted_services_ytd']
        ]

        mtd_total_cost = sum(sum(costs.values()) for _, costs in pdata['sorted_services_mtd']) if pdata['sorted_services_mtd'] else 0
        mtd_top_service_cost = sum(pdata['sorted_services_mtd'][0][1].values()) if pdata['sorted_services_mtd'] else 0
        mtd_avg_daily = sum(pdata['daily_totals_mtd'].values()) / len(pdata['dates_mtd']) if pdata['dates_mtd'] else 0
        mtd_services_count = len(pdata['sorted_services_mtd'])

        ytd_total_cost = sum(sum(costs.values()) for _, costs in pdata['sorted_services_ytd']) if pdata['sorted_services_ytd'] else 0
        ytd_top_service_cost = sum(pdata['sorted_services_ytd'][0][1].values()) if pdata['sorted_services_ytd'] else 0
        ytd_avg_daily = sum(pdata['daily_totals_ytd'].values()) / len(pdata['dates_ytd']) if pdata['dates_ytd'] else 0
        ytd_services_count = len(pdata['sorted_services_ytd'])

        # Generate JavaScript code with proper escaping
        html_content += '''
        allProfilesData['{}'] = {{
            mtd: {{
                dates: {},
                topServices: {},
                allServices: {},
                dailyTotals: {},
                stats: {{
                    totalCost: {:.2f},
                    topServiceCost: {:.2f},
                    avgDailyCost: {:.2f},
                    servicesCount: {}
                }}
            }},
            ytd: {{
                dates: {},
                topServices: {},
                allServices: {},
                dailyTotals: {},
                stats: {{
                    totalCost: {:.2f},
                    topServiceCost: {:.2f},
                    avgDailyCost: {:.2f},
                    servicesCount: {}
                }}
            }}
        }};
'''.format(
            profile_key,
            json.dumps(pdata['dates_mtd']),
            json.dumps(mtd_top_services),
            json.dumps(mtd_all_services),
            json.dumps(pdata['daily_totals_mtd']),
            mtd_total_cost,
            mtd_top_service_cost,
            mtd_avg_daily,
            mtd_services_count,
            json.dumps(pdata['dates_ytd']),
            json.dumps(ytd_top_services),
            json.dumps(ytd_all_services),
            json.dumps(pdata['daily_totals_ytd']),
            ytd_total_cost,
            ytd_top_service_cost,
            ytd_avg_daily,
            ytd_services_count
        )

html_content += '''
        // Current state
        let currentProfile = ''' + json.dumps('combined' if len(profiles) > 1 else profiles[0]) + ''';
        let currentView = 'mtd';

        // Date ranges
        const dateRangeMTD = '$START_DATE_MTD to $END_DATE_MTD';
        const dateRangeYTD = '$START_DATE_YTD to $END_DATE_YTD';

        // AWS Color palette
        const colors = [
            'rgba(255, 153, 0, 0.85)',     // AWS Orange
            'rgba(35, 47, 62, 0.85)',      // AWS Squid Ink
            'rgba(9, 114, 211, 0.85)',     // AWS Blue
            'rgba(3, 127, 12, 0.85)',      // AWS Green
            'rgba(209, 50, 18, 0.85)',     // AWS Red
            'rgba(136, 18, 128, 0.85)',    // AWS Purple
            'rgba(236, 114, 17, 0.85)',    // AWS Dark Orange
            'rgba(0, 125, 188, 0.85)',     // AWS Teal
            'rgba(96, 108, 118, 0.85)',    // AWS Gray
            'rgba(22, 25, 31, 0.85)'       // AWS Navy
        ];

        // Chart variable (will be initialized after DOM loads)
        let chart = null;

        // Initialize chart with current profile data
        function initializeChart() {
            const ctx = document.getElementById('dailyCostChart');
            if (!ctx) {
                console.error('Chart canvas not found');
                return;
            }

            const initialData = allProfilesData[currentProfile]['mtd'];
            chart = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: initialData.dates.map(d => d.substring(5)),
                    datasets: initialData.topServices.map((service, idx) => ({
                        ...service,
                        backgroundColor: colors[idx],
                        borderColor: colors[idx].replace('0.85', '1'),
                        borderWidth: 1
                    }))
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    interaction: {
                        mode: 'index',
                        intersect: false
                    },
                    plugins: {
                        legend: {
                            position: 'top',
                            labels: {
                                boxWidth: 12,
                                padding: 15,
                                font: {
                                    family: "'Amazon Ember', 'Open Sans', Arial, sans-serif",
                                    size: 13,
                                    weight: 600
                                },
                                color: '#232F3E'
                            }
                        },
                        title: {
                            display: true,
                            text: 'Daily Cost Breakdown - Top 10 Services (Stacked)',
                            font: {
                                size: 18,
                                weight: 700,
                                family: "'Amazon Ember', 'Open Sans', Arial, sans-serif"
                            },
                            color: '#232F3E',
                            padding: {
                                bottom: 20
                            }
                        },
                        tooltip: {
                            callbacks: {
                                label: function(context) {
                                    return context.dataset.label + ': \$' + context.parsed.y.toFixed(2);
                                },
                                footer: function(tooltipItems) {
                                    let total = 0;
                                    tooltipItems.forEach(function(tooltipItem) {
                                        total += tooltipItem.parsed.y;
                                    });
                                    return 'Total: \$' + total.toFixed(2);
                                }
                            }
                        }
                    },
                    scales: {
                        x: {
                            stacked: true,
                            grid: {
                                display: false
                            },
                            ticks: {
                                font: {
                                    family: "'Amazon Ember', 'Open Sans', Arial, sans-serif",
                                    size: 12
                                },
                                color: '#545b64'
                            }
                        },
                        y: {
                            stacked: true,
                            beginAtZero: true,
                            grid: {
                                color: '#e5e8eb'
                            },
                            ticks: {
                                callback: function(value) {
                                    return '\$' + value.toFixed(0);
                                },
                                font: {
                                    family: "'Amazon Ember', 'Open Sans', Arial, sans-serif",
                                    size: 12
                                },
                                color: '#545b64'
                            }
                        }
                    }
                }
            });
        }

        // Update AWS Info section
        function updateAwsInfo() {
            const infoContent = document.getElementById('awsInfoContent');

            if (currentProfile === 'combined') {
                // Show all profiles info
                let html = '';
                profiles.forEach(profile => {
                    const metadata = profileMetadata[profile];
                    html += '<div style="margin-bottom: 15px; padding-bottom: 15px; border-bottom: 1px solid #d5dbdb;">';
                    html += '<div class="info-row"><div class="info-label">Profile:</div><div class="info-value">' + profile + '</div></div>';
                    html += '<div class="info-row"><div class="info-label">Account ID:</div><div class="info-value">' + metadata.account_id + '</div></div>';
                    html += '<div class="info-row"><div class="info-label">Identity (ARN):</div><div class="info-value">' + metadata.identity + '</div></div>';
                    html += '</div>';
                });
                infoContent.innerHTML = html;
            } else {
                // Show single profile info
                const metadata = profileMetadata[currentProfile];
                let html = '';
                html += '<div class="info-row"><div class="info-label">Profile:</div><div class="info-value">' + currentProfile + '</div></div>';
                html += '<div class="info-row"><div class="info-label">Account ID:</div><div class="info-value">' + metadata.account_id + '</div></div>';
                html += '<div class="info-row"><div class="info-label">Identity (ARN):</div><div class="info-value">' + metadata.identity + '</div></div>';
                infoContent.innerHTML = html;
            }
        }

        // Switch profile function
        function switchProfile(profile) {
            try {
                currentProfile = profile;

                // Update profile tab buttons
                if (profiles.length > 1) {
                    document.querySelectorAll('.profile-tab').forEach(btn => {
                        btn.classList.remove('active');
                    });
                    const profileBtn = document.getElementById('profileBtn_' + profile);
                    if (profileBtn) {
                        profileBtn.classList.add('active');
                    }
                }

                // Update AWS info
                updateAwsInfo();

                // Refresh view with new profile data
                toggleView(currentView);
            } catch (error) {
                console.error('Error in switchProfile:', error);
            }
        }

        // Generate table HTML
        function generateTable(view) {
            const profileData = allProfilesData[currentProfile];
            if (!profileData) {
                console.error('Profile data not found in generateTable');
                return '<p>Error: Profile data not found</p>';
            }

            const viewData = profileData[view];
            if (!viewData) {
                console.error('View data not found in generateTable');
                return '<p>Error: View data not found</p>';
            }

            const dates = viewData.dates || [];
            const allServices = viewData.allServices || [];
            const dailyTotals = viewData.dailyTotals || {};

            // Detect anomalies
            const anomalies = detectAnomalies(dailyTotals);

            let tableHTML = '<table><thead>';

            // Group dates by month with month totals
            const monthsData = [];
            let currentMonth = null;
            dates.forEach(dateStr => {
                const date = new Date(dateStr);
                const monthKey = dateStr.substring(0, 7); // YYYY-MM
                const monthName = date.toLocaleDateString('en-US', { month: 'short', year: 'numeric' }); // "Jan 2026"

                if (!currentMonth || currentMonth.key !== monthKey) {
                    currentMonth = {
                        key: monthKey,
                        name: monthName,
                        dates: [],
                        serviceTotals: {},
                        dailyTotalsSum: 0
                    };
                    monthsData.push(currentMonth);
                }
                currentMonth.dates.push(dateStr);
            });

            // Calculate monthly totals for each service and overall
            allServices.forEach(service => {
                monthsData.forEach(monthInfo => {
                    const monthTotal = monthInfo.dates.reduce((sum, d) => sum + (service.costs[d] || 0), 0);
                    monthInfo.serviceTotals[service.name] = monthTotal;
                });
            });

            monthsData.forEach(monthInfo => {
                monthInfo.dailyTotalsSum = monthInfo.dates.reduce((sum, d) => sum + (dailyTotals[d] || 0), 0);
            });

            // First header row: Month names (every 7 days) and month total columns
            tableHTML += '<tr><th rowspan="2" style="background: #fafafa; vertical-align: middle;">Service</th>';
            monthsData.forEach(monthInfo => {
                const monthDates = monthInfo.dates;
                // Show month name every 7 days
                for (let i = 0; i < monthDates.length; i += 7) {
                    const remainingDays = Math.min(7, monthDates.length - i);
                    tableHTML += '<th colspan="' + remainingDays + '" style="background: #232F3E; color: #FF9900; border-bottom: 1px solid #FF9900; font-size: 11px;">' + monthInfo.name + '</th>';
                }
                // Month total column
                tableHTML += '<th rowspan="2" style="background: #FF9900; color: white; vertical-align: middle; font-size: 11px;">' + monthInfo.name.split(' ')[0] + '<br/>Total</th>';
            });
            // Grand total column
            tableHTML += '<th rowspan="2" style="background: #232F3E; color: white; vertical-align: middle;">Grand<br/>Total</th>';
            tableHTML += '</tr>';

            // Second header row: Day numbers
            tableHTML += '<tr>';
            monthsData.forEach(monthInfo => {
                monthInfo.dates.forEach(dateStr => {
                    const day = dateStr.substring(8); // Get DD part
                    const weekendClass = isWeekend(dateStr) ? ' class="weekend"' : '';
                    tableHTML += '<th' + weekendClass + ' style="font-size: 11px;">' + day + '</th>';
                });
            });
            tableHTML += '</tr></thead><tbody>';

            // Add service rows with month totals
            allServices.forEach(service => {
                tableHTML += '<tr>';
                const serviceName = service.name.length > 70 ? service.name.substring(0, 70) : service.name;
                const servicePct = ((service.total / Object.values(dailyTotals).reduce((sum, cost) => sum + cost, 0)) * 100).toFixed(1);
                tableHTML += '<td title="' + service.name + '">' + serviceName + '<span class="percentage">' + servicePct + '%</span></td>';

                // Add daily costs grouped by month with month totals
                monthsData.forEach(monthInfo => {
                    monthInfo.dates.forEach(date => {
                        const cost = service.costs[date] || 0;
                        const costClass = cost > 50 ? 'cost-high' : (cost > 10 ? 'cost-medium' : 'cost-low');
                        const costStr = cost > 0 ? cost.toFixed(2) : '-';
                        const weekendClass = isWeekend(date) ? ' weekend' : '';
                        const anomalyClass = anomalies.has(date) && cost > 10 ? ' anomaly' : '';
                        const anomalyIndicator = anomalies.has(date) && cost > 10 ? '<span class="anomaly-indicator">⚠</span>' : '';
                        tableHTML += '<td class="' + costClass + weekendClass + anomalyClass + '">' + costStr + anomalyIndicator + '</td>';
                    });

                    // Month total cell
                    const monthTotal = monthInfo.serviceTotals[service.name] || 0;
                    tableHTML += '<td style="font-weight: bold; background: #fff8e6; color: #232F3E; border-left: 2px solid #FF9900;">\$' + monthTotal.toFixed(2) + '</td>';
                });

                // Grand total cell
                tableHTML += '<td style="font-weight: bold; background: #fafafa; color: #232F3E; border-left: 2px solid #232F3E;">\$' + service.total.toFixed(2) + '</td>';
                tableHTML += '</tr>';
            });

            // Add total row with month totals
            tableHTML += '<tr class="total-row"><td>TOTAL</td>';

            let grandTotal = 0;
            monthsData.forEach(monthInfo => {
                // Daily totals for this month
                monthInfo.dates.forEach(date => {
                    const total = dailyTotals[date] || 0;
                    grandTotal += total;
                    const weekendClass = isWeekend(date) ? ' weekend' : '';
                    tableHTML += '<td class="' + weekendClass + '">\$' + total.toFixed(2) + '</td>';
                });

                // Month total cell
                tableHTML += '<td style="background: #FF9900; color: white; font-weight: 700; border-left: 2px solid white;">\$' + monthInfo.dailyTotalsSum.toFixed(2) + '</td>';
            });

            // Grand total cell
            tableHTML += '<td style="background: #232F3E; color: white; font-weight: 700; border-left: 2px solid white;">\$' + grandTotal.toFixed(2) + '</td>';
            tableHTML += '</tr></tbody></table>';

            return tableHTML;
        }

        // Toggle function
        function toggleView(view) {
            try {
                currentView = view;

                // Get profile data
                const profileData = allProfilesData[currentProfile];
                if (!profileData) {
                    console.error('Profile data not found for:', currentProfile);
                    return;
                }

                const viewData = profileData[view];
                if (!viewData) {
                    console.error('View data not found for:', view);
                    return;
                }

                // Update button states
                document.getElementById('mtdBtn').classList.toggle('active', view === 'mtd');
                document.getElementById('ytdBtn').classList.toggle('active', view === 'ytd');

                // Update subtitle
                const subtitle = view === 'mtd' ? '$MONTH_NAME • Month-to-Date Analysis' : '$MONTH_NAME • Year-to-Date Analysis';
                document.getElementById('subtitle').textContent = subtitle;

                // Update date range
                const dateRange = view === 'mtd' ? dateRangeMTD : dateRangeYTD;
                document.getElementById('dateRange').textContent = dateRange;

                // Update stats
                const stats = viewData.stats;
                document.getElementById('totalCost').textContent = '\$' + stats.totalCost.toFixed(2);
                document.getElementById('topService').textContent = '\$' + stats.topServiceCost.toFixed(2);
                document.getElementById('avgDaily').textContent = '\$' + stats.avgDailyCost.toFixed(2);
                document.getElementById('servicesCount').textContent = stats.servicesCount;

                // Update percentage for top service
                const topServicePct = ((stats.topServiceCost / stats.totalCost) * 100).toFixed(1);
                document.getElementById('topServicePct').textContent = topServicePct + '% of total';

                // Calculate and display forecast (only for MTD)
                const forecastElement = document.getElementById('forecastText');
                if (view === 'mtd' && viewData.dates && viewData.dates.length > 0) {
                    const forecast = calculateForecast(viewData.dates, viewData.dailyTotals);
                    if (forecast) {
                        const isPartialMonth = forecast.currentDay < forecast.lastDay;
                        if (isPartialMonth) {
                            const increase = forecast.forecastTotal - stats.totalCost;
                            const increasePercent = ((increase / stats.totalCost) * 100).toFixed(0);
                            forecastElement.innerHTML = '📈 Forecast: <strong>\$' + forecast.forecastTotal.toFixed(2) + '</strong> by month end<br/><span style="font-size: 12px;">(+\$' + increase.toFixed(2) + ', +' + increasePercent + '% from current)</span>';
                            forecastElement.className = 'forecast';
                        } else {
                            forecastElement.innerHTML = '✅ Month complete';
                            forecastElement.className = 'forecast';
                        }
                    } else {
                        forecastElement.innerHTML = '';
                    }
                } else {
                    forecastElement.innerHTML = '';
                }

                // Update chart
                if (chart) {
                    const dates = viewData.dates;
                    const topServices = viewData.topServices;

                    chart.data.labels = dates.map(d => d.substring(5));
                    chart.data.datasets = topServices.map((service, idx) => ({
                        ...service,
                        backgroundColor: colors[idx],
                        borderColor: colors[idx].replace('0.85', '1'),
                        borderWidth: 1
                    }));
                    chart.update();
                }

                // Update table
                const tableWrapper = document.querySelector('.table-wrapper');
                if (tableWrapper) {
                    tableWrapper.innerHTML = generateTable(view);
                }
            } catch (error) {
                console.error('Error in toggleView:', error);
            }
        }

        // Initialize on page load
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Initializing page...');
            console.log('Current profile:', currentProfile);
            console.log('Current view:', currentView);

            initializeChart();
            updateAwsInfo();

            // Initialize forecast and other dynamic content
            const profileData = allProfilesData[currentProfile];
            const viewData = profileData[currentView];

            console.log('View data:', viewData);
            console.log('Dates count:', viewData.dates.length);

            // Calculate forecast
            if (currentView === 'mtd' && viewData.dates && viewData.dates.length > 0) {
                const forecast = calculateForecast(viewData.dates, viewData.dailyTotals);
                console.log('Forecast data:', forecast);

                if (forecast) {
                    const forecastElement = document.getElementById('forecastText');
                    const isPartialMonth = forecast.currentDay < forecast.lastDay;

                    console.log('Is partial month:', isPartialMonth);
                    console.log('Current day:', forecast.currentDay);
                    console.log('Last day:', forecast.lastDay);

                    if (isPartialMonth) {
                        const stats = viewData.stats;
                        const increase = forecast.forecastTotal - stats.totalCost;
                        const increasePercent = ((increase / stats.totalCost) * 100).toFixed(0);
                        forecastElement.innerHTML = '📈 Forecast: <strong>\$' + forecast.forecastTotal.toFixed(2) + '</strong> by month end<br/><span style="font-size: 12px;">(+\$' + increase.toFixed(2) + ', +' + increasePercent + '% from current)</span>';
                        forecastElement.className = 'forecast';
                        console.log('Forecast displayed');
                    } else {
                        forecastElement.innerHTML = '✅ Month complete';
                        forecastElement.className = 'forecast';
                        console.log('Month complete displayed');
                    }
                }
            }

            // Call toggleView to update table and ensure everything is in sync
            toggleView(currentView);
        });
    </script>
</body>
</html>
'''

# Write to file
with open('$OUTPUT_FILE', 'w') as f:
    f.write(html_content)

print(f"✅ Report generated: $OUTPUT_FILE")
print(f"📊 Total services: {len(sorted_services)}")
print(f"📅 Date range: {dates[0]} to {dates[-1]}")
print(f"💰 Total cost: \${sum(daily_totals.values()):.2f}")
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Report generation complete!"
    echo "📄 File: $OUTPUT_FILE"
    echo ""
    echo "🌐 Open report with: open $OUTPUT_FILE"
else
    echo "❌ Error generating report"
    exit 1
fi

# Cleanup
for temp_file in "${TEMP_FILES_MTD[@]}" "${TEMP_FILES_YTD[@]}"; do
    rm -f "$temp_file"
done
