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
        PROFILES=($(grep -E '^\[.*\]$' ~/.aws/credentials | tr -d '[]' | grep -v '^default$'))
        
        if [[ ${#PROFILES[@]} -gt 0 ]]; then
            echo "🔍 Found AWS profiles in ~/.aws/credentials:"
            echo "   - default"
            for profile in "${PROFILES[@]}"; do
                echo "   - $profile"
            done
            echo ""
            echo "❓ Which profile would you like to use?"
            echo "   (Press Enter to use 'default', or type profile name)"
            read -r -p "Profile: " selected_profile
            
            if [[ -n "$selected_profile" ]]; then
                AWS_PROFILE="$selected_profile"
                echo "✅ Using profile: $AWS_PROFILE"
            else
                echo "✅ Using default profile"
            fi
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

# Calculate date range
START_DATE="${YEAR_MONTH}-01"
# Get last day of month
LAST_DAY=$(date -j -v1d -v+1m -v-1d -f "%Y-%m-%d" "$START_DATE" +%d 2>/dev/null || echo "31")
END_DATE="${YEAR_MONTH}-${LAST_DAY}"

echo "📊 Generating AWS Cost Report for $MONTH_NAME"
echo "   Date range: $START_DATE to $END_DATE"

# Fetch cost data from AWS
TEMP_FILE="/tmp/aws_costs_${YEAR_MONTH}.json"
echo "🔄 Fetching cost data from AWS..."

aws ce get-cost-and-usage \
    --time-period Start=$START_DATE,End=$END_DATE \
    --granularity DAILY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json > "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
    echo "❌ Error: Failed to fetch AWS cost data"
    exit 1
fi

echo "✅ Data fetched successfully"

# Generate HTML report
OUTPUT_FILE="$HOME/aws_cost_report_${YEAR_MONTH}.html"
echo "📝 Generating HTML report..."

python3 << EOF
import json
from datetime import datetime

with open('$TEMP_FILE', 'r') as f:
    data = json.load(f)

# Collect all services and dates
services = {}
dates = []

for day in data['ResultsByTime']:
    date = day['TimePeriod']['Start']
    dates.append(date)
    
    for group in day['Groups']:
        service = group['Keys'][0]
        cost = float(group['Metrics']['UnblendedCost']['Amount'])
        
        if service not in services:
            services[service] = {}
        services[service][date] = cost

# Filter out services with zero total cost
filtered_services = {}
for service, daily_costs in services.items():
    total = sum(daily_costs.values())
    if total > 0:
        filtered_services[service] = daily_costs

# Sort services by total cost (descending)
sorted_services = sorted(filtered_services.items(), key=lambda x: sum(x[1].values()), reverse=True)

# Calculate daily totals
daily_totals = {}
for date in dates:
    daily_total = sum(services[svc].get(date, 0) for svc in filtered_services)
    daily_totals[date] = daily_total

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
    </style>
</head>
<body>
    <div class="container">
        <h1>AWS Cost Report</h1>
        <p style="color: #86868b; margin-top: 5px;">$MONTH_NAME • Month-to-Date Analysis</p>
        
        <div class="summary">
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
        const ctx = document.getElementById('dailyCostChart');
        
        const dates = ''' + json.dumps([d[5:] for d in dates]) + ''';
        
        // Top 10 services for stacked bar chart
        const topServices = ''' + json.dumps([
            {
                'label': service[:40],
                'data': [costs.get(d, 0) for d in dates],
            }
            for service, costs in sorted_services[:10]
        ]) + ''';
        
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
        
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: dates,
                datasets: topServices.map((service, idx) => ({
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
rm -f "$TEMP_FILE"
