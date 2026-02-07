# AWS Cost Report Generator by Yod

Generate beautiful, interactive HTML reports of your AWS costs with daily breakdowns, charts, and service-level details.

![AWS Cost Report](https://img.shields.io/badge/AWS-Cost%20Report-orange?style=flat-square&logo=amazon-aws)
![Shell Script](https://img.shields.io/badge/Shell-Script-green?style=flat-square&logo=gnu-bash)
![Python](https://img.shields.io/badge/Python-3.x-blue?style=flat-square&logo=python)

## Features

- 📊 **Interactive Charts** - Stacked bar charts showing daily cost breakdown by service
- 📋 **Detailed Tables** - Complete service-by-service daily cost breakdown with percentages
- 🎨 **Weekend Highlighting** - Visual distinction between weekdays and weekends
- 💰 **Cost Analytics** - Summary cards showing total cost, top service, average daily cost
- 📈 **Cost Forecasting** - Predicts end-of-month costs based on current spending trends
- ⚠️ **Anomaly Detection** - Automatically highlights days with unusual cost spikes
- 📥 **CSV Export** - Download cost data as CSV for further analysis
- 📊 **Percentage Analysis** - Shows each service's percentage of total costs
- 📱 **Responsive Design** - Works on desktop and mobile browsers
- 🔄 **MTD & YTD Views** - Switch between Month-to-Date and Year-to-Date analysis
- 👥 **Multi-Profile Support** - Combine or compare costs across multiple AWS accounts

## Sample Output

The generated report includes:
- **Summary Cards** with key metrics:
  - Total cost with forecast prediction for month-end
  - Top service cost with percentage breakdown
  - Average daily cost
  - Total number of services
- **Interactive Stacked Bar Chart** showing top 10 services over time
- **Comprehensive Data Table** with:
  - All services and daily costs
  - Service percentage of total costs
  - Monthly and grand totals
  - Weekend columns highlighted in blue
  - Anomaly detection (cost spikes marked with ⚠️)
  - Color-coded costs (red for high, orange for medium, green for low)
- **Export Functionality** - Download data as CSV
- **Multi-View Toggle** - Switch between MTD and YTD analysis
- **Multi-Profile Support** - View combined or individual AWS account costs

## Prerequisites

- **AWS CLI** - Installed and configured ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- **AWS Credentials** - Valid credentials with Cost Explorer permissions
- **Python 3** - For HTML report generation
- **macOS/Linux** - Bash shell environment

### Required AWS Permissions

Your AWS credentials need the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage"
      ],
      "Resource": "*"
    }
  ]
}
```

## Installation

1. Clone this repository:
```bash
git clone https://github.com/tkosin/aws-cost-report-generator.git
cd aws-cost-report-generator
```

2. Make the script executable:
```bash
chmod +x generate_aws_cost_report.sh
```

3. Verify AWS credentials:
```bash
aws sts get-caller-identity
```

## Advanced Features

### 📈 Cost Forecasting

The report automatically calculates projected costs for the end of the month based on current spending patterns:
- Uses linear regression on existing data
- Shows forecast total and estimated additional costs
- Displays percentage increase from current
- Only shown for partial months (automatically hidden for complete months)

Example: *"Forecast: $1,234.56 by month end (+$234.56, +23% from current)"*

### ⚠️ Anomaly Detection

Automatically identifies unusual cost spikes using statistical analysis:
- Calculates mean and standard deviation of daily costs
- Highlights days that exceed 2 standard deviations above mean
- Marks anomalies with ⚠️ indicator in the table
- Red border around anomalous cells for visibility

This helps quickly identify:
- Unexpected resource usage
- Configuration errors
- Cost optimization opportunities

### 📊 Percentage Analysis

Every service shows its contribution to total costs:
- Service percentages displayed in table rows
- Top service percentage in summary card
- Helps identify cost concentration
- Easy to spot which services dominate spending

### 📥 CSV Export

Download the complete cost data for further analysis:
- Click "Export CSV" button in the top-right corner
- Includes all services and daily breakdowns
- Preserves monthly and grand totals
- File named: `aws_cost_report_{profile}_{view}_{month}.csv`

Perfect for:
- Importing into Excel or Google Sheets
- Creating custom reports
- Long-term cost tracking
- Budget planning

### 👥 Multi-Profile Support

Analyze costs across multiple AWS accounts:
- **Interactive Profile Selection** - Choose from detected AWS profiles at runtime
- **Combined View** - See aggregated costs across all selected accounts
- **Individual Views** - Switch between profiles to see account-specific costs
- **Account Information** - Display AWS Account ID and IAM identity for verification

## Usage

### Basic Usage

Generate a report for the current month:
```bash
./generate_aws_cost_report.sh
```

### Specify a Month

Generate a report for a specific month:
```bash
./generate_aws_cost_report.sh 2026-01
./generate_aws_cost_report.sh 2025-12
```

### Using AWS Profiles

**Interactive Profile Selection** (Recommended):
```bash
./generate_aws_cost_report.sh 2026-01
# Script will detect available profiles and prompt you to select
# Select multiple profiles: 1,2,4
```

**Single Profile**:
```bash
./generate_aws_cost_report.sh 2026-01 --profile production
```

**Multiple Profiles** (comma-separated):
```bash
./generate_aws_cost_report.sh 2026-01 --profiles prod,dev,staging
```

**Using Environment Variable**:
```bash
AWS_PROFILE=production ./generate_aws_cost_report.sh 2026-01
```

### Help

Show help message:
```bash
./generate_aws_cost_report.sh --help
```

## Output

The script generates an HTML file in your home directory with the format:

**Single Profile:**
```
~/aws_cost_report_2026-01_default_123456789012.html
```

**Multiple Profiles:**
```
~/aws_cost_report_2026-01_prod+dev+staging_123456789012+987654321098+567890123456.html
```

The filename includes:
- Date (YYYY-MM)
- Profile name(s) (joined with +)
- AWS Account ID(s) (joined with +)

Open the report in your browser:
```bash
open ~/aws_cost_report_2026-01_*.html
```

### Report Features

The generated HTML report is:
- **Self-contained** - Single file with embedded CSS and JavaScript
- **Interactive** - Switch between MTD/YTD views and profiles
- **Exportable** - Download data as CSV
- **Shareable** - Send the HTML file to colleagues
- **Offline-capable** - Works without internet (after Chart.js loads once)

## AWS Credential Configuration

The script uses the standard AWS credential chain in the following order:

1. **Environment Variables**
   ```bash
   export AWS_ACCESS_KEY_ID=your_key_id
   export AWS_SECRET_ACCESS_KEY=your_secret_key
   export AWS_REGION=us-east-1
   ```

2. **AWS Profile**
   ```bash
   export AWS_PROFILE=your_profile
   ```

3. **Shared Credentials File** (`~/.aws/credentials`)
   ```ini
   [default]
   aws_access_key_id = AKIAIOSFODNN7EXAMPLE
   aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
   ```

4. **IAM Role** (when running on EC2/ECS)

## Troubleshooting

### AWS CLI Not Found
```bash
# Install AWS CLI
brew install awscli  # macOS
# Or follow: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
```

### Invalid Credentials
```bash
# Configure AWS credentials
aws configure

# Or verify existing credentials
aws sts get-caller-identity
```

### No Cost Data
- Ensure Cost Explorer is enabled in your AWS account
- Wait 24 hours after enabling Cost Explorer for data to appear
- Verify your IAM permissions include `ce:GetCostAndUsage`

### Python Not Found
```bash
# Install Python 3
brew install python3  # macOS
```

## Tips & Best Practices

### Understanding Your Report

**Forecast Accuracy:**
- Forecasts are most accurate mid-month (after day 10)
- Early month forecasts may be less reliable
- Spiky workloads may show less accurate projections
- Use forecast as a guide, not absolute prediction

**Interpreting Anomalies:**
- Red warnings (⚠️) indicate unusual cost spikes
- Common causes:
  - Data transfer spikes
  - Compute instance size changes
  - Database backup operations
  - Development/testing activities
- Click on anomaly dates to investigate in AWS Cost Explorer

**Using Percentages:**
- Services >50% indicate potential single points of cost optimization
- Many small services (<5%) may indicate over-diversification
- Compare percentages month-over-month to spot trends

**Export and Analysis:**
- Export to CSV for custom pivot tables
- Compare multiple months side-by-side
- Create budget tracking spreadsheets
- Share data with finance teams

### Multi-Account Best Practices

**Profile Selection:**
- Select all accounts to see organizational total
- Switch to individual profiles to drill down
- Use consistent profile names across your team

**Cost Allocation:**
- Each profile shows AWS Account ID for verification
- Use profile names that match your organization structure
- Consider separate reports for different cost centers

## Examples

### Monthly Cost Review
Generate reports for the last 3 months:
```bash
./generate_aws_cost_report.sh 2026-01
./generate_aws_cost_report.sh 2025-12
./generate_aws_cost_report.sh 2025-11
```

### Multi-Account Setup
Generate reports for different AWS accounts:
```bash
AWS_PROFILE=account1 ./generate_aws_cost_report.sh 2026-01
AWS_PROFILE=account2 ./generate_aws_cost_report.sh 2026-01
AWS_PROFILE=account3 ./generate_aws_cost_report.sh 2026-01
```

### Automated Monthly Reports
Add to crontab for automatic monthly report generation:
```bash
# Run on the 1st of every month at 9 AM
0 9 1 * * cd ~/aws-cost-report-generator && ./generate_aws_cost_report.sh
```

## Technical Details

### Cost Data
- **Data Source:** AWS Cost Explorer API (`aws ce get-cost-and-usage`)
- **Granularity:** Daily
- **Metric:** UnblendedCost (actual costs without reserved instance or savings plan discounts)
- **Grouping:** By AWS Service
- **Date Ranges:**
  - MTD (Month-to-Date): First day to last day of selected month
  - YTD (Year-to-Date): January 1st to last day of selected month

### Report Format
- Single HTML file with embedded CSS and JavaScript
- No external dependencies (except Chart.js from CDN)
- Works offline after initial load
- File size: ~100-500KB depending on data volume

### Forecasting Algorithm
- **Method:** Linear regression based on average daily cost
- **Formula:** `Forecast = (Total Cost / Days Elapsed) × Days in Month`
- **Accuracy:** Best for consistent daily patterns; less accurate for highly variable workloads
- **Display:** Only shown for partial months (hidden when month is complete)

### Anomaly Detection Algorithm
- **Method:** Statistical outlier detection using standard deviation
- **Threshold:** 2 standard deviations above mean
- **Criteria:** Only flags costs above mean (ignores low-cost anomalies)
- **Minimum Data:** Requires at least 3 days of data
- **Visual Indicator:** Red border with ⚠️ symbol

### Chart Library
- [Chart.js](https://www.chartjs.org/) v4.4.0 for interactive visualizations
- Stacked bar chart showing top 10 services
- Responsive and mobile-friendly

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - feel free to use this in your own projects.

## Author

Created by [tkosin](https://github.com/tkosin)

## Acknowledgments

- AWS Cost Explorer API
- Chart.js for beautiful charts
- The AWS community for cost optimization insights
