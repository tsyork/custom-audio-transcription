#!/bin/bash

# AWS AMI Builder for Whisper Transcription
# This script creates a pre-built AMI with all dependencies installed
# Usage: ./create-whisper-ami.sh

set -e

echo "🏗️ Building Whisper Transcription AMI"
echo "======================================"

# Step 1: Launch a temporary instance for AMI creation
echo "📦 Step 1: Launching temporary instance for AMI creation..."

# Check that spot-fleet-config.json exists in config directory
if [ ! -f "config/spot-fleet-config.json" ]; then
    echo "❌ config/spot-fleet-config.json not found"
    echo "Please run this script from your custom-audio-transcription repository directory"
    echo "Expected file structure:"
    echo "  custom-audio-transcription/"
    echo "  ├── config/"
    echo "  │   ├── spot-fleet-config.json"
    echo "  │   └── credentials.json"
    echo "  └── create-whisper-ami.sh"
    exit 1
fi

# Extract configuration from your existing spot-fleet-config.json
echo "📋 Reading configuration from config/spot-fleet-config.json..."
SECURITY_GROUP=$(python3 -c "import json; data=json.load(open('config/spot-fleet-config.json')); print(data['LaunchSpecifications'][0]['SecurityGroups'][0]['GroupId'])")
SUBNET_LIST=$(python3 -c "import json; data=json.load(open('config/spot-fleet-config.json')); print(data['LaunchSpecifications'][0]['SubnetId'])")
FIRST_SUBNET=$(echo $SUBNET_LIST | cut -d',' -f1)
KEY_NAME=$(python3 -c "import json; data=json.load(open('config/spot-fleet-config.json')); print(data['LaunchSpecifications'][0]['KeyName'])")

echo "Security Group: $SECURITY_GROUP"
echo "Using Subnet: $FIRST_SUBNET (first from: $SUBNET_LIST)"
echo "Key Name: $KEY_NAME"

# Check that the SSH key exists (add .pem extension if needed)
if [ ! -f "$KEY_NAME" ]; then
    # Try with .pem extension
    if [ ! -f "${KEY_NAME}.pem" ]; then
        echo "❌ SSH key '$KEY_NAME' not found in current directory"
        echo "Looking for key file relative to script location..."
        if [ -f "config/${KEY_NAME}.pem" ]; then
            KEY_PATH="config/${KEY_NAME}.pem"
            echo "✅ Found SSH key at: $KEY_PATH"
        elif [ -f "config/$KEY_NAME" ]; then
            KEY_PATH="config/$KEY_NAME"
            echo "✅ Found SSH key at: $KEY_PATH"
        else
            echo "SSH key not found. Checked locations:"
            echo "  - $KEY_NAME"
            echo "  - ${KEY_NAME}.pem"
            echo "  - config/$KEY_NAME"
            echo "  - config/${KEY_NAME}.pem"
            exit 1
        fi
    else
        KEY_PATH="${KEY_NAME}.pem"
        echo "✅ Found SSH key at: $KEY_PATH"
    fi
else
    KEY_PATH="$KEY_NAME"
    echo "✅ Found SSH key at: $KEY_PATH"
fi

# Get the latest Ubuntu 20.04 AMI for current region
echo "🔍 Finding latest Ubuntu 20.04 AMI for current region..."
CURRENT_REGION=$(aws configure get region)
echo "Current AWS region: $CURRENT_REGION"

UBUNTU_AMI=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

if [ "$UBUNTU_AMI" = "None" ] || [ -z "$UBUNTU_AMI" ]; then
    echo "❌ Could not find Ubuntu 20.04 AMI in region $CURRENT_REGION"
    echo "Trying Ubuntu 22.04 as fallback..."
    UBUNTU_AMI=$(aws ec2 describe-images \
      --owners 099720109477 \
      --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
      --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
      --output text)
fi

if [ "$UBUNTU_AMI" = "None" ] || [ -z "$UBUNTU_AMI" ]; then
    echo "❌ Could not find suitable Ubuntu AMI in region $CURRENT_REGION"
    exit 1
fi

echo "✅ Using Ubuntu AMI: $UBUNTU_AMI"

# Launch instance for AMI creation using on-demand for reliability
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $UBUNTU_AMI \
  --instance-type g4dn.xlarge \
  --key-name $KEY_NAME \
  --security-group-ids $SECURITY_GROUP \
  --subnet-id $FIRST_SUBNET \
  --block-device-mappings '[{
    "DeviceName": "/dev/sda1",
    "Ebs": {
      "VolumeSize": 50,
      "VolumeType": "gp3",
      "DeleteOnTermination": true
    }
  }]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=whisper-ami-builder}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance launched: $INSTANCE_ID"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Instance IP: $PUBLIC_IP"

# Wait for SSH to be ready
echo "⏳ Waiting for SSH to be ready..."
for i in {1..20}; do
    if ssh -i $KEY_PATH -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "echo 'ready'" >/dev/null 2>&1; then
        echo "✅ SSH ready!"
        break
    fi
    echo "   Attempt $i/20..."
    sleep 15
done

# Step 2: Run the complete setup on the instance
echo "🔧 Step 2: Installing all dependencies on instance..."

# Create the setup script (extracted from your deploy-transcription.sh)
cat > ami-setup-script.sh << 'SETUP'
#!/bin/bash

# This is the same setup from your deploy-transcription.sh startup script
# but optimized for AMI creation

# Log everything
exec > /home/ubuntu/ami-setup.log 2>&1

echo "🚀 Starting AMI setup for Whisper transcription..."

# Update system and install ALL base dependencies (matching your working script)
echo "📦 Installing system dependencies..."
apt update -y
apt install -y software-properties-common curl ffmpeg

# Add Python 3.12 repository and install (matching your working script exactly)
echo "📦 Installing Python 3.12..."
add-apt-repository ppa:deadsnakes/ppa -y
apt update
apt install -y python3.12 python3.12-venv python3.12-dev

# Get pip for Python 3.12
echo "📥 Installing pip for Python 3.12..."
curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# Create virtual environment as ubuntu user
echo "🔧 Creating virtual environment..."
cd /home/ubuntu
sudo -u ubuntu python3.12 -m venv transcription-env

# Install Python packages as ubuntu user
echo "📦 Installing Python packages..."
sudo -u ubuntu bash -c "
source /home/ubuntu/transcription-env/bin/activate
pip install --upgrade pip setuptools wheel
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip install openai-whisper google-api-python-client google-auth google-cloud-storage tqdm certifi
"

# Install NVIDIA drivers
echo "🎮 Installing NVIDIA drivers..."
apt install -y ubuntu-drivers-common
ubuntu-drivers autoinstall

# Create activation helper script that properly activates the environment
cat > /home/ubuntu/activate-transcription.sh << 'ACTIVATE'
#!/bin/bash
cd /home/ubuntu

# Activate the Python virtual environment
source transcription-env/bin/activate

# Set environment variables
export CUDA_VISIBLE_DEVICES=0
export PATH=/usr/local/cuda/bin:$PATH

echo "🚀 Transcription environment activated!"
echo "Python version: $(python --version)"
echo "Working directory: $(pwd)"

# Check GPU status
echo "GPU Status:"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null || echo "GPU info will be available after reboot"
else
    echo "nvidia-smi not available (will be available after reboot)"
fi

# Test CUDA availability
echo "CUDA Available: $(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'Will be available after environment activation')"
echo ""
ACTIVATE

chown ubuntu:ubuntu /home/ubuntu/activate-transcription.sh
chmod +x /home/ubuntu/activate-transcription.sh

# Create a startup template that the fast deployment will use
cat > /home/ubuntu/fast-deployment-template.sh << 'TEMPLATE'
#!/bin/bash

# Fast deployment startup script for pre-built AMI
exec > /home/ubuntu/startup.log 2>&1

echo "⚡ Starting FAST deployment with pre-built AMI..."
echo "Timestamp: $(date)"

# Wait for instance to be fully ready
sleep 10

# Verify AMI is properly configured
if [ ! -f /home/ubuntu/ami-ready.txt ]; then
    echo "❌ This doesn't appear to be a properly configured Whisper AMI!"
    echo "AMI ready file not found"
    exit 1
fi

echo "✅ Pre-built AMI verified"
echo "✅ Python environment ready at: /home/ubuntu/transcription-env"
echo "✅ Activation script ready at: /home/ubuntu/activate-transcription.sh"

# Create quick-start script that will be customized by deployment
cat > /home/ubuntu/quick-start.sh << 'QUICKSTART'
#!/bin/bash
cd /home/ubuntu

echo "📂 Waiting for deployment files..."
while [ ! -f test_ami.py ] && [ ! -f interactive_transcribe.py ]; do
    echo "   Waiting for files... ($(date +%H:%M:%S))"
    sleep 5
done

echo "🚀 Files received! Activating pre-built environment..."

# Use the pre-built activation script
source /home/ubuntu/activate-transcription.sh

echo "🧪 Running tests or transcription..."

# Check what files were deployed and run accordingly
if [ -f test_ami.py ]; then
    echo "Running AMI validation test..."
    python test_ami.py
elif [ -f interactive_transcribe.py ]; then
    echo "Running interactive transcription..."
    # This would be customized by the deployment script
    python interactive_transcribe.py
else
    echo "No recognized script found"
fi

echo "✅ Quick start complete!"
QUICKSTART

chown ubuntu:ubuntu /home/ubuntu/quick-start.sh
chmod +x /home/ubuntu/quick-start.sh

# Signal that startup is complete
echo "ready" > /home/ubuntu/setup-complete.txt
chown ubuntu:ubuntu /home/ubuntu/setup-complete.txt

echo "✅ Fast deployment startup complete!"
TEMPLATE

chown ubuntu:ubuntu /home/ubuntu/fast-deployment-template.sh
chmod +x /home/ubuntu/fast-deployment-template.sh

# Verify all installations before creating AMI
echo "🔍 Verifying installations..."
sudo -u ubuntu bash -c "
source /home/ubuntu/transcription-env/bin/activate
echo 'Testing FFmpeg:'
ffmpeg -version | head -1
echo 'Testing Python packages:'
python -c 'import whisper; print(\"✅ Whisper:\", whisper.__version__)'
python -c 'import torch; print(\"✅ PyTorch:\", torch.__version__)'
python -c 'import google.cloud.storage; print(\"✅ Google Cloud Storage: OK\")'
python -c 'import google.auth; print(\"✅ Google Auth: OK\")'
python -c 'import tqdm; print(\"✅ TQDM: OK\")'
echo 'Testing CUDA availability (will show after reboot):'
python -c 'import torch; print(\"CUDA available:\", torch.cuda.is_available())'
"

# Clean up to reduce AMI size
echo "🧹 Cleaning up..."
apt autoclean
apt autoremove -y
rm -rf /var/log/*.log
rm -rf /tmp/*
rm -rf /var/cache/apt/archives/*.deb

# Create AMI ready indicator
echo "ready" > /home/ubuntu/ami-ready.txt
chown ubuntu:ubuntu /home/ubuntu/ami-ready.txt

echo "✅ AMI setup complete!"
SETUP

# Copy and run the setup script with better error handling
echo "📤 Deploying setup script to instance..."
scp -i $KEY_PATH -o StrictHostKeyChecking=no ami-setup-script.sh ubuntu@$PUBLIC_IP:~/

echo "🔧 Running AMI setup script..."
if ! ssh -i $KEY_PATH -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "sudo bash ami-setup-script.sh"; then
    echo "❌ AMI setup script failed!"
    echo "Checking logs..."
    ssh -i $KEY_PATH -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "tail -20 ami-setup.log 2>/dev/null || echo 'No setup log found'"
    exit 1
fi

echo "✅ AMI setup script completed successfully"

# Verify the setup was successful
echo "🔍 Verifying AMI setup..."
ssh -i $KEY_PATH -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "
echo 'Checking AMI ready marker:'
ls -la ami-ready.txt 2>/dev/null || echo 'AMI ready marker not found'

echo 'Checking virtual environment:'
ls -la transcription-env/ 2>/dev/null || echo 'Virtual environment not found'

echo 'Checking activation script:'
ls -la activate-transcription.sh 2>/dev/null || echo 'Activation script not found'

echo 'Checking fast deployment template:'
ls -la fast-deployment-template.sh 2>/dev/null || echo 'Fast deployment template not found'

echo 'Testing basic imports:'
source transcription-env/bin/activate 2>/dev/null && python -c 'import whisper, torch; print(\"Basic imports successful\")' 2>/dev/null || echo 'Import test failed'
"

echo "✅ Setup completed on instance"

# Step 3: Create the AMI
echo "📸 Step 3: Creating AMI from configured instance..."

# Wait a moment for everything to settle
sleep 30

AMI_ID=$(aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "whisper-transcription-ready-$(date +%Y%m%d-%H%M)" \
  --description "Pre-configured Ubuntu 20.04 with Python 3.12, PyTorch, Whisper, and NVIDIA drivers for transcription" \
  --no-reboot \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Name,Value=whisper-transcription-ami},{Key=Purpose,Value=audio-transcription},{Key=Repository,Value=custom-audio-transcription}]' \
  --query 'ImageId' \
  --output text)

echo "✅ AMI creation started: $AMI_ID"

# Step 4: Wait for AMI to be ready
echo "⏳ Step 4: Waiting for AMI to be available..."
echo "This usually takes 5-10 minutes..."

aws ec2 wait image-available --image-ids $AMI_ID
echo "✅ AMI is ready!"

# Step 5: Clean up temporary instance
echo "🧹 Step 5: Cleaning up temporary instance..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID >/dev/null
echo "✅ Temporary instance terminated"

# Step 6: Update spot-fleet-config.json with new AMI ID
echo "🔧 Step 6: Updating config/spot-fleet-config.json with new AMI..."

# Create backup
cp config/spot-fleet-config.json config/spot-fleet-config.json.backup

# Update AMI ID in config file using Python for reliable JSON editing
python3 -c "
import json
with open('config/spot-fleet-config.json', 'r') as f:
    config = json.load(f)
config['LaunchSpecifications'][0]['ImageId'] = '$AMI_ID'
with open('config/spot-fleet-config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('✅ Updated config/spot-fleet-config.json with AMI: $AMI_ID')
"

# Clean up setup script
rm ami-setup-script.sh

echo ""
echo "🎉 AMI CREATION COMPLETE! 🎉"
echo "=========================="
echo "New AMI ID: $AMI_ID"
echo "Updated: spot-fleet-config.json"
echo "Backup: spot-fleet-config.json.backup"
echo ""
echo "📋 Next Steps:"
echo "1. Test the new AMI: ./deploy-transcription-fast.sh"
echo "2. Your instances will now launch in ~3 minutes instead of 20+ minutes"
echo "3. AMI storage cost: ~$0.75-1.00/month"
echo ""
echo "🔍 Verify AMI details:"
echo "aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].[Name,Description,State]' --output table"