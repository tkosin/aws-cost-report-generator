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
#   --profile PROFILE   AWS profile to use (default: default)
#   --help              Show this help message
#
# Examples:
#   ./generate_aws_cost_report.sh                    # Current month
#   ./generate_aws_cost_report.sh 2026-01           # January 2026
#   ./generate_aws_cost_report.sh 2026-01 --profile yodkosin
#   AWS_PROFILE=prod ./generate_aws_cost_report.sh  # Using environment variable
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
AWS_PROFILE=""
MONTH_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --profile)
            AWS_PROFILE="$2"
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

# If profile not specified, check if user has multiple profiles and ask
if [[ -z "$AWS_PROFILE" ]] && [[ -z "$AWS_DEFAULT_PROFILE" ]]; then
    if [[ -f ~/.aws/credentials ]]; then
        # Get list of profiles from credentials file
        PROFILES=($(grep -E '^\[.*\]$' ~/.aws/credentials | tr -d '[]'))
        
        if [[ ${#PROFILES[@]} -gt 1 ]]; then
            echo "🔍 Found AWS profiles in ~/.aws/credentials"
            echo ""
            echo "❓ Select AWS profile (use arrow keys):"
            
            PS3="Profile: "
            select selected_profile in "${PROFILES[@]}"; do
                if [[ -n "$selected_profile" ]]; then
                    AWS_PROFILE="$selected_profile"
                    echo ""
                    echo "✅ Using profile: $AWS_PROFILE"
                    break
                else
                    echo "Invalid selection. Please try again."
                fi
            done
            echo ""
        elif [[ ${#PROFILES[@]} -eq 1 ]]; then
            AWS_PROFILE="${PROFILES[0]}"
            echo "🔍 Found single AWS profile: $AWS_PROFILE"
            echo ""
        fi
    fi
fi

# Set AWS profile if specified
if [[ -n "$AWS_PROFILE" ]]; then
    export AWS_PROFILE
    echo "🔐 AWS Profile: $AWS_PROFILE"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS credentials not configured or invalid"
    echo ""
    echo "   Configure credentials:"
    echo "   1. Run: aws configure"
    echo "   2. Or set environment variables:"
    echo "      export AWS_ACCESS_KEY_ID=your_key"
    echo "      export AWS_SECRET_ACCESS_KEY=your_secret"
    echo "   3. Or use a profile:"
    echo "      export AWS_PROFILE=your_profile"
    echo ""
    exit 1
fi

echo "✅ AWS credentials validated"
AWS_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
AWS_USER_ID=$(aws sts get-caller-identity --query 'UserId' --output text)
echo "   Using: $AWS_IDENTITY"
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

# Fetch MTD cost data from AWS
TEMP_FILE_MTD="/tmp/aws_costs_mtd_${YEAR_MONTH}.json"
echo "🔄 Fetching MTD cost data from AWS..."

aws ce get-cost-and-usage \
    --time-period Start=$START_DATE_MTD,End=$END_DATE_MTD \
    --granularity DAILY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json > "$TEMP_FILE_MTD"

if [ ! -s "$TEMP_FILE_MTD" ]; then
    echo "❌ Error: Failed to fetch MTD AWS cost data"
    exit 1
fi

echo "✅ MTD data fetched successfully"

# Fetch YTD cost data from AWS
TEMP_FILE_YTD="/tmp/aws_costs_ytd_${YEAR_MONTH}.json"
echo "🔄 Fetching YTD cost data from AWS..."

aws ce get-cost-and-usage \
    --time-period Start=$START_DATE_YTD,End=$END_DATE_YTD \
    --granularity DAILY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json > "$TEMP_FILE_YTD"

if [ ! -s "$TEMP_FILE_YTD" ]; then
    echo "❌ Error: Failed to fetch YTD AWS cost data"
    exit 1
fi

echo "✅ YTD data fetched successfully"

# Generate HTML report
# Create filename with profile and account ID
PROFILE_NAME="${AWS_PROFILE:-default}"
OUTPUT_FILE="$HOME/aws_cost_report_${YEAR_MONTH}_${PROFILE_NAME}-${AWS_ACCOUNT_ID}.html"
echo "📝 Generating HTML report..."

python3 << EOF
import json
from datetime import datetime

# Load MTD data
with open('$TEMP_FILE_MTD', 'r') as f:
    data_mtd = json.load(f)

# Load YTD data
with open('$TEMP_FILE_YTD', 'r') as f:
    data_ytd = json.load(f)

# Process MTD data
services_mtd = {}
dates_mtd = []

for day in data_mtd['ResultsByTime']:
    date = day['TimePeriod']['Start']
    dates_mtd.append(date)
    
    for group in day['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        
        if service not in services_mtd:
            services_mtd[service] = {}
        services_mtd[service][date] = cost

# Process YTD data
services_ytd = {}
dates_ytd = []

for day in data_ytd['ResultsByTime']:
    date = day['TimePeriod']['Start']
    dates_ytd.append(date)
    
    for group in day['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        
        if service not in services_ytd:
            services_ytd[service] = {}
        services_ytd[service][date] = cost

# Filter MTD services with zero total cost
filtered_services_mtd = {}
for service, daily_costs in services_mtd.items():
    total = sum(daily_costs.values())
    if total > 0:
        filtered_services_mtd[service] = daily_costs

# Filter YTD services with zero total cost
filtered_services_ytd = {}
for service, daily_costs in services_ytd.items():
    total = sum(daily_costs.values())
    if total > 0:
        filtered_services_ytd[service] = daily_costs

# Sort services by total cost (descending)
sorted_services_mtd = sorted(filtered_services_mtd.items(), key=lambda x: sum(x[1].values()), reverse=True)
sorted_services_ytd = sorted(filtered_services_ytd.items(), key=lambda x: sum(x[1].values()), reverse=True)

# Calculate daily totals for MTD
daily_totals_mtd = {}
for date in dates_mtd:
    daily_total = sum(services_mtd[svc].get(date, 0) for svc in filtered_services_mtd)
    daily_totals_mtd[date] = daily_total

# Calculate daily totals for YTD
daily_totals_ytd = {}
for date in dates_ytd:
    daily_total = sum(services_ytd[svc].get(date, 0) for svc in filtered_services_ytd)
    daily_totals_ytd[date] = daily_total

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
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f7;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 12px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        h1 {
            color: #1d1d1f;
            margin-bottom: 10px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0 40px 0;
        }
        .summary-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
        }
        .summary-card h3 {
            margin: 0 0 5px 0;
            font-size: 14px;
            opacity: 0.9;
        }
        .summary-card p {
            margin: 0;
            font-size: 28px;
            font-weight: bold;
        }
        .chart-container {
            margin: 40px 0;
            height: 500px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 30px;
            font-size: 13px;
        }
        th, td {
            padding: 10px 8px;
            text-align: right;
            border-bottom: 1px solid #e5e5e7;
        }
        th:first-child, td:first-child {
            text-align: left;
            position: sticky;
            left: 0;
            background: white;
            font-weight: 500;
            max-width: 300px;
        }
        th {
            background: #f5f5f7;
            font-weight: 600;
            position: sticky;
            top: 0;
            z-index: 10;
        }
        th.weekend {
            background: #e3f2fd;
            color: #1976d2;
        }
        td.weekend {
            background: #f1f8ff;
        }
        tbody tr:hover td:not(:first-child) {
            background: #fff9e6;
        }
        tbody tr:hover td.weekend {
            background: #e3f2fd;
        }
        tbody tr:hover td:first-child {
            background: #fafafa;
        }
        .total-row {
            font-weight: bold;
        }
        .total-row td:first-child {
            background: #f0f0f2 !important;
        }
        .total-row td {
            background: #f0f0f2;
        }
        .total-row td.weekend {
            background: #d1e7fd !important;
        }
        .table-wrapper {
            overflow-x: auto;
            margin-top: 20px;
        }
        .cost-high { color: #d32f2f; font-weight: 600; }
        .cost-medium { color: #f57c00; }
        .cost-low { color: #388e3c; }
        .aws-info {
            background: #f5f5f7;
            padding: 15px 20px;
            border-radius: 8px;
            margin: 20px 0;
            font-size: 13px;
        }
        .aws-info h3 {
            margin: 0 0 10px 0;
            font-size: 14px;
            color: #1d1d1f;
        }
        .aws-info .info-row {
            display: flex;
            margin: 5px 0;
        }
        .aws-info .info-label {
            font-weight: 600;
            color: #515154;
            min-width: 120px;
        }
        .aws-info .info-value {
            color: #1d1d1f;
            font-family: 'SF Mono', Monaco, monospace;
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
        }
        .toggle-switch {
            display: inline-flex;
            background: #e5e5e7;
            border-radius: 8px;
            padding: 4px;
        }
        .toggle-option {
            padding: 10px 24px;
            border: none;
            background: transparent;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            color: #515154;
            border-radius: 6px;
            transition: all 0.3s ease;
        }
        .toggle-option.active {
            background: white;
            color: #667eea;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .toggle-option:hover:not(.active) {
            color: #1d1d1f;
        }
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-row">
            <div class="header-left">
                <h1 style="margin: 0;">AWS Cost Report</h1>
                <p style="color: #86868b; margin: 5px 0 0 0;" id="subtitle">$MONTH_NAME • Month-to-Date Analysis</p>
                <p style="color: #86868b; margin: 2px 0 0 0; font-size: 13px;" id="dateRange">$START_DATE_MTD to $END_DATE_MTD</p>
            </div>
            <div class="toggle-container">
                <div class="toggle-switch">
                    <button class="toggle-option active" id="mtdBtn" onclick="toggleView('mtd')">MTD</button>
                    <button class="toggle-option" id="ytdBtn" onclick="toggleView('ytd')">YTD</button>
                </div>
            </div>
        </div>
        
        <div class="aws-info">
            <h3>📋 AWS Account Information</h3>
            <div class="info-row">
                <div class="info-label">Profile:</div>
                <div class="info-value">''' + ("""${AWS_PROFILE:-default}""") + '''</div>
            </div>
            <div class="info-row">
                <div class="info-label">Account ID:</div>
                <div class="info-value">$AWS_ACCOUNT_ID</div>
            </div>
            <div class="info-row">
                <div class="info-label">Identity (ARN):</div>
                <div class="info-value">$AWS_IDENTITY</div>
            </div>
        </div>
        
        <div class="summary" id="summary">
            <div class="summary-card">
                <h3>Total Cost</h3>
                <p>\$''' + f"{sum(sum(costs.values()) for _, costs in sorted_services):.2f}" + '''</p>
            </div>
            <div class="summary-card" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">
                <h3>Top Service</h3>
                <p>\$''' + f"{sum(sorted_services[0][1].values()):.2f}" + '''</p>
            </div>
            <div class="summary-card" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                <h3>Avg Daily Cost</h3>
                <p>\$''' + f"{sum(daily_totals.values()) / len(dates):.2f}" + '''</p>
            </div>
            <div class="summary-card" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%);">
                <h3>Services</h3>
                <p>''' + str(len(sorted_services)) + '''</p>
            </div>
        </div>

        <div class="chart-container">
            <canvas id="dailyCostChart"></canvas>
        </div>

        <h2 style="margin-top: 50px;">All AWS Services - Daily Breakdown</h2>
        <div class="table-wrapper">
            <table>
                <thead>
                    <tr>
                        <th>Service</th>
'''

# Add date headers with weekend styling
for date in dates:
    weekend_class = ' class="weekend"' if is_weekend(date) else ''
    html_content += f'                        <th{weekend_class}>{date[5:]}</th>\\n'
html_content += '                        <th style="background: #e3e3e5;">Total</th>\\n'
html_content += '''                    </tr>
                </thead>
                <tbody>
'''

# Add ALL service rows with weekend styling
for service, costs in sorted_services:
    total = sum(costs.values())
    html_content += f'                    <tr>\\n'
    html_content += f'                        <td title="{service}">{service[:70]}</td>\\n'
    
    for date in dates:
        cost = costs.get(date, 0)
        cost_class = 'cost-high' if cost > 50 else ('cost-medium' if cost > 10 else 'cost-low')
        cost_str = f'{cost:.2f}' if cost > 0 else '-'
        weekend_class = ' weekend' if is_weekend(date) else ''
        html_content += f'                        <td class="{cost_class}{weekend_class}">{cost_str}</td>\\n'
    
    html_content += f'                        <td style="font-weight: bold; background: #f5f5f7;">\${total:.2f}</td>\\n'
    html_content += f'                    </tr>\\n'

# Add total row with weekend styling
html_content += '                    <tr class="total-row">\\n'
html_content += '                        <td>TOTAL</td>\\n'
for date in dates:
    weekend_class = ' weekend' if is_weekend(date) else ''
    html_content += f'                        <td class="{weekend_class}">\${daily_totals[date]:.2f}</td>\\n'
html_content += f'                        <td style="background: #e3e3e5;">\${sum(daily_totals.values()):.2f}</td>\\n'
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
        
        // MTD Data
        const datesMTD = ''' + json.dumps(dates_mtd) + ''';
        const topServicesMTD = ''' + json.dumps([
            {
                'label': service[:40],
                'data': [costs.get(d, 0) for d in dates_mtd],
            }
            for service, costs in sorted_services_mtd[:10]
        ]) + ''';
        const allServicesMTD = ''' + json.dumps([
            {
                'name': service,
                'costs': {d: costs.get(d, 0) for d in dates_mtd},
                'total': sum(costs.values())
            }
            for service, costs in sorted_services_mtd
        ]) + ''';
        const dailyTotalsMTD = ''' + json.dumps(daily_totals_mtd) + ''';
        const statsMTD = {
            totalCost: ''' + f"{sum(sum(costs.values()) for _, costs in sorted_services_mtd):.2f}" + ''',
            topServiceCost: ''' + f"{sum(sorted_services_mtd[0][1].values()):.2f}" + ''',
            avgDailyCost: ''' + f"{sum(daily_totals_mtd.values()) / len(dates_mtd):.2f}" + ''',
            servicesCount: ''' + str(len(sorted_services_mtd)) + '''
        };
        
        // YTD Data
        const datesYTD = ''' + json.dumps(dates_ytd) + ''';
        const topServicesYTD = ''' + json.dumps([
            {
                'label': service[:40],
                'data': [costs.get(d, 0) for d in dates_ytd],
            }
            for service, costs in sorted_services_ytd[:10]
        ]) + ''';
        const allServicesYTD = ''' + json.dumps([
            {
                'name': service,
                'costs': {d: costs.get(d, 0) for d in dates_ytd},
                'total': sum(costs.values())
            }
            for service, costs in sorted_services_ytd
        ]) + ''';
        const dailyTotalsYTD = ''' + json.dumps(daily_totals_ytd) + ''';
        const statsYTD = {
            totalCost: ''' + f"{sum(sum(costs.values()) for _, costs in sorted_services_ytd):.2f}" + ''',
            topServiceCost: ''' + f"{sum(sorted_services_ytd[0][1].values()):.2f}" + ''',
            avgDailyCost: ''' + f"{sum(daily_totals_ytd.values()) / len(dates_ytd):.2f}" + ''',
            servicesCount: ''' + str(len(sorted_services_ytd)) + '''
        };
        
        // Date ranges
        const dateRangeMTD = '$START_DATE_MTD to $END_DATE_MTD';
        const dateRangeYTD = '$START_DATE_YTD to $END_DATE_YTD';
        
        // Current view
        let currentView = 'mtd';
        
        // Color palette
        const colors = [
            'rgba(255, 99, 132, 0.8)',
            'rgba(54, 162, 235, 0.8)',
            'rgba(255, 206, 86, 0.8)',
            'rgba(75, 192, 192, 0.8)',
            'rgba(153, 102, 255, 0.8)',
            'rgba(255, 159, 64, 0.8)',
            'rgba(199, 199, 199, 0.8)',
            'rgba(83, 102, 255, 0.8)',
            'rgba(255, 99, 255, 0.8)',
            'rgba(50, 205, 50, 0.8)'
        ];
        
        // Initialize chart
        const ctx = document.getElementById('dailyCostChart');
        let chart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: datesMTD,
                datasets: topServicesMTD.map((service, idx) => ({
                    ...service,
                    backgroundColor: colors[idx],
                    borderColor: colors[idx].replace('0.8', '1'),
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
                            padding: 10
                        }
                    },
                    title: {
                        display: true,
                        text: 'Daily Cost Breakdown - Top 10 Services (Stacked)',
                        font: { size: 16 }
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
                    },
                    y: {
                        stacked: true,
                        beginAtZero: true,
                        ticks: {
                            callback: function(value) {
                                return '\$' + value.toFixed(0);
                            }
                        }
                    }
                }
            }
        });
        
        // Generate table HTML
        function generateTable(view) {
            const dates = view === 'mtd' ? datesMTD : datesYTD;
            const allServices = view === 'mtd' ? allServicesMTD : allServicesYTD;
            const dailyTotals = view === 'mtd' ? dailyTotalsMTD : dailyTotalsYTD;
            
            let tableHTML = '<table><thead><tr><th>Service</th>';
            
            // Add date headers
            dates.forEach(date => {
                const dateLabel = date.substring(5); // Get MM-DD part
                const weekendClass = isWeekend(date) ? ' class="weekend"' : '';
                tableHTML += '<th' + weekendClass + '>' + dateLabel + '</th>';
            });
            tableHTML += '<th style="background: #e3e3e5;">Total</th></tr></thead><tbody>';
            
            // Add service rows
            allServices.forEach(service => {
                tableHTML += '<tr>';
                const serviceName = service.name.length > 70 ? service.name.substring(0, 70) : service.name;
                tableHTML += '<td title="' + service.name + '">' + serviceName + '</td>';
                
                dates.forEach(date => {
                    const cost = service.costs[date] || 0;
                    const costClass = cost > 50 ? 'cost-high' : (cost > 10 ? 'cost-medium' : 'cost-low');
                    const costStr = cost > 0 ? cost.toFixed(2) : '-';
                    const weekendClass = isWeekend(date) ? ' weekend' : '';
                    tableHTML += '<td class="' + costClass + weekendClass + '">' + costStr + '</td>';
                });
                
                tableHTML += '<td style="font-weight: bold; background: #f5f5f7;">\$' + service.total.toFixed(2) + '</td>';
                tableHTML += '</tr>';
            });
            
            // Add total row
            tableHTML += '<tr class="total-row"><td>TOTAL</td>';
            let grandTotal = 0;
            dates.forEach(date => {
                const total = dailyTotals[date] || 0;
                grandTotal += total;
                const weekendClass = isWeekend(date) ? ' weekend' : '';
                tableHTML += '<td class="' + weekendClass + '">\$' + total.toFixed(2) + '</td>';
            });
            tableHTML += '<td style="background: #e3e3e5;">\$' + grandTotal.toFixed(2) + '</td>';
            tableHTML += '</tr></tbody></table>';
            
            return tableHTML;
        }
        
        // Toggle function
        function toggleView(view) {
            currentView = view;
            
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
            const stats = view === 'mtd' ? statsMTD : statsYTD;
            const summaryCards = document.querySelectorAll('.summary-card p');
            summaryCards[0].textContent = '\$' + stats.totalCost.toFixed(2);
            summaryCards[1].textContent = '\$' + stats.topServiceCost.toFixed(2);
            summaryCards[2].textContent = '\$' + stats.avgDailyCost.toFixed(2);
            summaryCards[3].textContent = stats.servicesCount;
            
            // Update chart
            const dates = view === 'mtd' ? datesMTD : datesYTD;
            const topServices = view === 'mtd' ? topServicesMTD : topServicesYTD;
            
            chart.data.labels = dates.map(d => d.substring(5));
            chart.data.datasets = topServices.map((service, idx) => ({
                ...service,
                backgroundColor: colors[idx],
                borderColor: colors[idx].replace('0.8', '1'),
                borderWidth: 1
            }));
            chart.update();
            
            // Update table
            const tableWrapper = document.querySelector('.table-wrapper');
            tableWrapper.innerHTML = generateTable(view);
        }
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
rm -f "$TEMP_FILE_MTD" "$TEMP_FILE_YTD"
