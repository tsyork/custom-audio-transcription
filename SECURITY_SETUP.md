# Security Setup Guide

This document explains how to securely configure credentials for the custom audio transcription system.

## 🔐 Authentication Overview

This project requires three types of authentication:
1. **AWS CLI** - For spot fleet management (no files stored)
2. **Google Cloud Service Account** - For storage and docs access
3. **AWS SSH Key** - For instance access

## 🛡️ Security Principles

- **No credentials are stored in this repository**
- **All sensitive files are git-ignored**
- **Each user must configure their own credentials**
- **Templates are provided for configuration**

## ⚙️ Setup Instructions

### 1. AWS CLI Authentication

Configure AWS CLI with your credentials (no files needed in project):

```bash
# Install AWS CLI
brew install awscli

# Configure with your AWS access keys
aws configure
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Access Key]  
# Default region name: us-east-1
# Default output format: json

# Test authentication
aws sts get-caller-identity
```

**Security**: AWS credentials are stored in `~/.aws/credentials` (outside this project).

### 2. Google Cloud Service Account

Create a service account with the following APIs enabled:
- Google Drive API
- Google Docs API  
- Google Cloud Storage API

**Steps:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create new service account or use existing
3. Download JSON key file
4. **Save as:** `config/credentials.json` (this file is git-ignored)
5. Share your Google Drive folders with the service account email

**Required permissions:**
```json
{
  "scopes": [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/documents", 
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}
```

### 3. AWS SSH Key

Create an EC2 key pair for instance access:

**Steps:**
1. Go to [AWS EC2 Console](https://console.aws.amazon.com/ec2)
2. Navigate to Key Pairs
3. Create new key pair (download .pem file)
4. **Save as:** `config/whisper-transcription-key.pem` (this file is git-ignored)
5. Set permissions: `chmod 400 config/whisper-transcription-key.pem`

### 4. Spot Fleet Configuration

Configure your AWS-specific settings:

**Steps:**
1. Copy template: `cp config/spot-fleet-config.template.json config/spot-fleet-config.json`
2. Replace placeholders in `config/spot-fleet-config.json`:
   - `YOUR_ACCOUNT_ID` - Your AWS account ID
   - `YOUR_AMI_ID` - Ubuntu 22.04 LTS AMI for your region
   - `YOUR_SUBNET_ID` - VPC subnet ID
   - `YOUR_SECURITY_GROUP_ID` - Security group allowing SSH (port 22)
   - `YOUR_KEY_NAME` - Name of your EC2 key pair

**Find your values:**
```bash
# Account ID
aws sts get-caller-identity --query Account --output text

# Latest Ubuntu 22.04 AMI
aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text

# Default VPC subnet
aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text

# Default security group  
aws ec2 describe-security-groups --group-names default --query 'SecurityGroups[0].GroupId' --output text
```

## ✅ Verification

Test that all authentication is working:

```bash
# Test AWS access
aws sts get-caller-identity

# Test Google Cloud access (requires credentials.json)
python3 -c "
from google.oauth2 import service_account
from google.cloud import storage
creds = service_account.Credentials.from_service_account_file('config/credentials.json')
client = storage.Client(credentials=creds)
print('✅ Google Cloud authentication successful')
"

# Test SSH key permissions
ls -la config/whisper-transcription-key.pem
# Should show: -r-------- (400 permissions)
```

## 🚨 Security Warnings

### Never commit these files:
- `config/credentials.json` - Contains private keys
- `config/whisper-transcription-key.pem` - SSH private key
- `config/spot-fleet-config.json` - May contain account IDs
- Any files in `logs/` - May contain sensitive runtime data

### Best practices:
- Rotate service account keys regularly
- Use least-privilege IAM policies
- Monitor AWS billing for unexpected charges
- Delete resources when not in use

## 🆘 Troubleshooting

### "AccessDenied" errors
- Check that AWS CLI is configured correctly
- Verify IAM user has EC2 and IAM permissions

### "Service account not found"
- Verify `config/credentials.json` file exists and is valid JSON
- Check that the service account has required API access

### "Permission denied" for SSH
- Verify SSH key file permissions: `chmod 400 config/whisper-transcription-key.pem`
- Ensure key name in spot-fleet-config.json matches EC2 key pair name

### Google Drive access issues
- Verify the AI Transcripts folder is shared with your service account email
- Check that the service account has Editor permissions on the folder