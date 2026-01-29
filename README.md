# AWS Cost Report Generator by Yod

Generate beautiful, interactive HTML reports of your AWS costs with daily breakdowns, charts, and service-level details.

![AWS Cost Report](https://img.shields.io/badge/AWS-Cost%20Report-orange?style=flat-square&logo=amazon-aws)
![Shell Script](https://img.shields.io/badge/Shell-Script-green?style=flat-square&logo=gnu-bash)
![Python](https://img.shields.io/badge/Python-3.x-blue?style=flat-square&logo=python)

## Features

- 📊 **Interactive Charts** - Stacked bar charts showing daily cost breakdown by service
- 📋 **Detailed Tables** - Complete service-by-service daily cost breakdown
- 🎨 **Weekend Highlighting** - Visual distinction between weekdays and weekends
- 💰 **Cost Analytics** - Summary cards showing total cost, top service, average daily cost
- 📱 **Responsive Design** - Works on desktop and mobile browsers
- 🔄 **Month-to-Date** - Automatic date range calculation for any month

## Sample Output

The generated report includes:
- Summary cards with key metrics
- Stacked bar chart showing top 10 services over time
- Comprehensive table with all services and daily costs
- Weekend columns highlighted in blue
- Color-coded costs (red for high, orange for medium, green for low)

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

Use a specific AWS profile:
```bash
AWS_PROFILE=production ./generate_aws_cost_report.sh 2026-01
```

Or export it first:
```bash
export AWS_PROFILE=production
./generate_aws_cost_report.sh 2026-01
```

### Help

Show help message:
```bash
./generate_aws_cost_report.sh --help
```

## Output

The script generates an HTML file named `aws_cost_report_YYYY-MM.html` in your home directory:

```
~/aws_cost_report_2026-01.html
```

Open the report in your browser:
```bash
open ~/aws_cost_report_2026-01.html
```

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
- Data source: AWS Cost Explorer API
- Granularity: Daily
- Metric: UnblendedCost (actual costs without reserved instance or savings plan discounts)
- Grouping: By AWS Service

### Report Format
- Single HTML file with embedded CSS and JavaScript
- No external dependencies (except Chart.js from CDN)
- Works offline after initial load

### Chart Library
- [Chart.js](https://www.chartjs.org/) v4.4.0 for interactive visualizations

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
