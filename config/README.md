# Configuration Setup

This directory contains templates and instructions for setting up the required configuration files.

## Required Files (NOT included in repository for security)

### 1. `credentials.json` - Google Cloud Service Account
- Download from Google Cloud Console
- Service account with Drive, Docs, and Storage API access
- Place in this directory as `config/credentials.json`

### 2. `whisper-transcription-key.pem` - AWS SSH Key
- Create in AWS EC2 Console → Key Pairs
- Download the .pem file
- Place in this directory as `config/whisper-transcription-key.pem`
- Set permissions: `chmod 400 config/whisper-transcription-key.pem`

### 3. `spot-fleet-config.json` - AWS Spot Fleet Configuration
- Copy from `spot-fleet-config.template.json`
- Replace all `YOUR_*` placeholders with your actual AWS values
- Save as `config/spot-fleet-config.json`

## Quick Setup Commands

```bash
# 1. Copy template and customize
cp config/spot-fleet-config.template.json config/spot-fleet-config.json
nano config/spot-fleet-config.json  # Replace YOUR_* placeholders

# 2. Add your Google Cloud credentials
# (Download from Google Cloud Console)
cp ~/Downloads/your-service-account.json config/credentials.json

# 3. Add your AWS SSH key
# (Download from AWS EC2 Console)
cp ~/Downloads/your-key.pem config/whisper-transcription-key.pem
chmod 400 config/whisper-transcription-key.pem
```

## Finding Your AWS Values

### Account ID
```bash
aws sts get-caller-identity --query Account --output text
```

### Latest Ubuntu 22.04 AMI
```bash
aws ec2 describe-images --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text
```

### Default VPC Subnet
```bash
aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text
```

### Default Security Group
```bash
aws ec2 describe-security-groups --group-names default \
  --query 'SecurityGroups[0].GroupId' --output text
```

## Security Note

These files are gitignored and will never be committed to the repository. Each user must create their own configuration files.

## Verification

Run the security audit to ensure setup is correct:
```bash
./security_audit.sh
```

Should show:
```
🎉 SECURITY AUDIT PASSED!
✅ No sensitive information detected
✅ Safe to push to GitHub
```

## Troubleshooting

### "Permission denied" for SSH key
```bash
chmod 400 config/whisper-transcription-key.pem
```

### "Service account not found"
- Verify `credentials.json` is valid JSON
- Check service account has required API permissions

### AWS "AccessDenied" errors
- Verify AWS CLI is configured: `aws sts get-caller-identity`
- Check IAM user has EC2 and IAM permissions
