#!/bin/bash

# One-Command Custom Audio Transcription Deployment
# Usage: ./deploy_custom.sh

set -e

echo "🎙️ Custom Audio Transcription - One-Command Deploy"
echo "=================================================="

# Change to script directory
cd "$(dirname "$0")"

# Check required files
echo "📋 Checking required files..."
required_files=("../config/spot-fleet-config.json" "../config/credentials.json" "../config/whisper-transcription-key.pem")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Missing required file: $file"
        echo "💡 Copy from your podcast transcription project"
        exit 1
    fi
done
echo "✅ All required files present"

# Check if audio files are uploaded
echo "📂 Checking for audio files in GCS..."
audio_count=$(gsutil ls gs://custom-transcription/audio_files/*.m4a 2>/dev/null | wc -l || echo "0")
if [ "$audio_count" -eq 0 ]; then
    echo "❌ No audio files found in GCS bucket!"
    echo ""
    echo "📤 Please upload your .m4a files first:"
    echo "   gsutil cp your_file1.m4a gs://custom-transcription/audio_files/"
    echo "   gsutil cp your_file2.m4a gs://custom-transcription/audio_files/"
    echo "   gsutil cp your_file3.m4a gs://custom-transcription/audio_files/"
    echo ""
    echo "Or use the helper script:"
    echo "   ./upload_files.sh *.m4a"
    exit 1
fi

echo "✅ Found $audio_count audio files in GCS"

# Launch Spot Fleet
echo "🚀 Launching AWS Spot Fleet..."
FLEET_ID=$(aws ec2 request-spot-fleet --spot-fleet-request-config file://../config/spot-fleet-config.json --query 'SpotFleetRequestId' --output text)
echo "Fleet ID: $FLEET_ID"

# Wait for instance
echo "⏳ Waiting for instance to launch..."
while true; do
    STATUS=$(aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids $FLEET_ID --query 'SpotFleetRequestConfigs[0].ActivityStatus' --output text)
    if [ "$STATUS" = "fulfilled" ]; then
        break
    fi
    echo "   Status: $STATUS - waiting..."
    sleep 10
done

# Get instance details
echo "📍 Getting instance details..."
INSTANCE_ID=$(aws ec2 describe-spot-fleet-instances --spot-fleet-request-id $FLEET_ID --query 'ActiveInstances[0].InstanceId' --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "✅ Instance ready!"
echo "   Instance ID: $INSTANCE_ID"
echo "   Public IP: $PUBLIC_IP"

# Wait for instance to be ready for SSH
echo "⏳ Waiting for instance to accept SSH connections..."
while ! ssh -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$PUBLIC_IP "echo 'connected'" &>/dev/null; do
    echo "   Waiting for SSH..."
    sleep 10
done

# Setup instance
echo "⚙️ Setting up instance environment..."
ssh -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP << 'SETUP'
# Update system and install Python 3.12
sudo apt update -y
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev

# Get pip for Python 3.12
curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

# Create virtual environment
python3.12 -m venv transcription-env
source transcription-env/bin/activate

# Install Python packages
pip install --upgrade pip setuptools wheel
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
pip install openai-whisper google-api-python-client google-auth google-cloud-storage tqdm certifi

# Install NVIDIA drivers
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
SETUP

# Copy files to instance
echo "📂 Copying files to instance..."
scp -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no simple_transcribe.py ubuntu@$PUBLIC_IP:~/
scp -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no ../config/credentials.json ubuntu@$PUBLIC_IP:~/

# Reboot to load NVIDIA drivers
echo "🔄 Rebooting instance to load NVIDIA drivers..."
ssh -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "sudo reboot" || true

# Wait for reboot
echo "⏳ Waiting for instance reboot..."
sleep 60
while ! ssh -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$PUBLIC_IP "echo 'rebooted'" &>/dev/null; do
    echo "   Waiting for reboot..."
    sleep 10
done

# Start transcription
echo "🎙️ Starting transcription process..."
ssh -i ../config/whisper-transcription-key.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "source transcription-env/bin/activate && python simple_transcribe.py" &

# Save fleet info for cleanup
echo $FLEET_ID > ../logs/fleet_id_$(date +%Y%m%d_%H%M%S)
echo $PUBLIC_IP > ../logs/instance_ip_$(date +%Y%m%d_%H%M%S)

# Display final info
echo ""
echo "📊 TRANSCRIPTION STARTED"
echo "======================="
echo "Fleet ID: $FLEET_ID"
echo "Instance: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo ""
echo "🔍 Monitor progress:"
echo "   ssh -i ../config/whisper-transcription-key.pem ubuntu@$PUBLIC_IP"
echo "   source transcription-env/bin/activate"
echo "   # Transcription is already running in background"
echo ""
echo "🛑 Stop when complete:"
echo "   ./cleanup.sh $FLEET_ID"
echo ""
echo "📁 Results will be saved to 'Custom Audio Transcripts' folder in Google Drive"
echo ""
echo "💰 Estimated cost: ~$0.75 for your audio files"
echo "The instance will auto-shutdown when transcription is complete."
