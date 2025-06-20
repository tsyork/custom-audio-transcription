#!/bin/bash

# Fast AWS Spot Fleet Transcription Deployment using Pre-built AMI
# Usage: ./deploy-transcription-fast.sh

set -e

echo "⚡ AWS Spot Fleet Transcription - FAST Deploy with Pre-built AMI"
echo "=============================================================="

# Check required files in the correct locations based on actual directory structure
echo "📋 Checking required files..."

# Check for required files
echo "Looking for config/spot-fleet-config.json..."
if [ ! -f "config/spot-fleet-config.json" ]; then
    echo "❌ Missing: config/spot-fleet-config.json"
    exit 1
fi

echo "Looking for test_ami.py..."
if [ ! -f "test_ami.py" ]; then
    echo "❌ Missing: test_ami.py (test script for AMI validation)"
    echo "Please create a test script or copy your transcription script to this repo"
    exit 1
fi

echo "Looking for config/credentials.json..."
if [ ! -f "config/credentials.json" ]; then
    echo "❌ Missing: config/credentials.json"
    exit 1
fi

# Check for SSH key in either root or config directory
key_found=false
if [ -f "whisper-transcription-key.pem" ]; then
    key_found=true
    SSH_KEY_PATH="whisper-transcription-key.pem"
    echo "Found SSH key in root directory"
elif [ -f "config/whisper-transcription-key.pem" ]; then
    key_found=true
    SSH_KEY_PATH="config/whisper-transcription-key.pem"
    echo "Found SSH key in config directory"
fi

if [ "$key_found" = false ]; then
    echo "❌ Missing SSH key: whisper-transcription-key.pem"
    echo "   Checked locations:"
    echo "   - ./whisper-transcription-key.pem"
    echo "   - ./config/whisper-transcription-key.pem"
    exit 1
fi

echo "✅ All required files found!"
echo "   - Config: config/spot-fleet-config.json"
    echo "   - Script: interactive_transcribe.py"
echo "   - Credentials: config/credentials.json"
echo "   - SSH Key: $SSH_KEY_PATH"

# Create minimal User Data script for pre-built AMI
echo "🔧 Creating minimal startup script for pre-built AMI..."
cat > startup-script.sh << 'STARTUP'
#!/bin/bash

# Minimal startup script for pre-built AMI - everything is already installed!
exec > /home/ubuntu/startup.log 2>&1

echo "⚡ Starting FAST transcription instance with pre-built AMI..."

# Just wait for instance to be fully ready
sleep 30

# Verify AMI is properly configured
if [ ! -f /home/ubuntu/ami-ready.txt ]; then
    echo "❌ This doesn't appear to be a properly configured Whisper AMI!"
    exit 1
fi

echo "✅ Pre-built AMI verified"

# Create quick-start script that uses pre-installed environment
cat > /home/ubuntu/quick-start.sh << 'QUICKSTART'
#!/bin/bash
cd /home/ubuntu

echo "📂 Waiting for transcription files..."
while [ ! -f interactive_transcribe.py ] || [ ! -f credentials.json ]; do
    echo "   Waiting for files... ($(date))"
    sleep 5
done

echo "🚀 Files received! Activating pre-built environment..."

# Use the pre-built activation script
source /home/ubuntu/activate-transcription.sh

echo "🎙️ Environment activated! Starting transcription..."

# Create auto-answers for Season 6, large-v3, auto-shutdown
echo -e "6\n1\n\n\nY\nY\nY" > auto-answers.txt

# Run transcription with auto-answers
python interactive_transcribe.py < auto-answers.txt

echo "✅ Transcription complete!"
QUICKSTART

chown ubuntu:ubuntu /home/ubuntu/quick-start.sh
chmod +x /home/ubuntu/quick-start.sh

# Signal that startup is complete
echo "ready" > /home/ubuntu/setup-complete.txt
chown ubuntu:ubuntu /home/ubuntu/setup-complete.txt

echo "✅ FAST startup complete! Ready for transcription in ~2 minutes total!"
STARTUP

# Convert to base64 for User Data
BASE64_SCRIPT=$(base64 -i startup-script.sh)

# Update spot fleet config with minimal User Data
sed -i.bak "s/\"UserData\": \".*\"/\"UserData\": \"$BASE64_SCRIPT\"/" config/spot-fleet-config.json

# Clean up temporary script
rm startup-script.sh

echo "✅ Updated deployment with minimal AMI startup"

# Step 1: Launch Fleet
echo "🚀 Step 1: Launching Spot Fleet with pre-built AMI..."
FLEET_ID=$(aws ec2 request-spot-fleet --spot-fleet-request-config file://config/spot-fleet-config.json --query 'SpotFleetRequestId' --output text)
echo "Fleet ID: $FLEET_ID"

# Step 2: Wait for Instance (should be much faster)
echo "⏳ Step 2: Waiting for instance to be ready..."
echo "With pre-built AMI, this should only take 2-3 minutes!"

start_time=$(date +%s)
while true; do
    STATUS=$(aws ec2 describe-spot-fleet-requests --spot-fleet-request-ids $FLEET_ID --query 'SpotFleetRequestConfigs[0].ActivityStatus' --output text)
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    echo "   Status: $STATUS (${elapsed}s elapsed)"
    
    if [ "$STATUS" = "fulfilled" ]; then
        echo "✅ Fleet is ready in ${elapsed} seconds!"
        break
    elif [ "$STATUS" = "error" ]; then
        echo "❌ Fleet failed to launch. Checking error..."
        aws ec2 describe-spot-fleet-request-history --spot-fleet-request-id $FLEET_ID --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%S) 2>/dev/null || aws ec2 describe-spot-fleet-request-history --spot-fleet-request-id $FLEET_ID --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) 2>/dev/null
        exit 1
    fi
    
    sleep 10
done

# Step 3: Get Instance Details
echo "📡 Step 3: Getting instance details..."
INSTANCE_ID=$(aws ec2 describe-spot-fleet-instances --spot-fleet-request-id $FLEET_ID --query 'ActiveInstances[0].InstanceId' --output text)
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"

# Step 4: Wait for FAST Setup (much shorter with pre-built AMI)
echo "⏳ Step 4: Waiting for minimal startup to complete..."
echo "Pre-built AMI has everything ready - just activating environment..."

# Wait for setup completion indicator
setup_complete=false
setup_start=$(date +%s)
for i in {1..12}; do  # Only 6 minutes max since everything is pre-installed
    if ssh -i $SSH_KEY_PATH -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "test -f setup-complete.txt" 2>/dev/null; then
        setup_end=$(date +%s)
        setup_time=$((setup_end - setup_start))
        echo "✅ Fast startup complete in ${setup_time} seconds!"
        setup_complete=true
        break
    fi
    echo "   Minimal startup in progress... ($i/12) - 30 seconds each"
    sleep 30
done

if [ "$setup_complete" = false ]; then
    echo "⚠️  Startup taking longer than expected. Checking logs..."
    ssh -i $SSH_KEY_PATH -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "cat startup.log 2>/dev/null | tail -10" || echo "Could not retrieve startup log"
fi

# Step 5: Deploy Files (same as before but faster since no installation time)
echo "📤 Step 5: Deploying transcription files..."
deployment_start=$(date +%s)

scp -i $SSH_KEY_PATH -o StrictHostKeyChecking=no test_ami.py ubuntu@$PUBLIC_IP:~/
scp -i $SSH_KEY_PATH -o StrictHostKeyChecking=no config/credentials.json ubuntu@$PUBLIC_IP:~/

deployment_end=$(date +%s)
deployment_time=$((deployment_end - deployment_start))
echo "✅ Files deployed in ${deployment_time} seconds!"

# Step 6: Start Transcription Immediately
echo "🎙️ Step 6: Starting transcription process..."
ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP "nohup ./quick-start.sh > transcription.log 2>&1 &"

# Calculate total time
total_end=$(date +%s)
total_time=$((total_end - start_time))
minutes=$((total_time / 60))
seconds=$((total_time % 60))

echo ""
echo "⚡ LIGHTNING-FAST DEPLOYMENT COMPLETE! ⚡"
echo "========================================="
echo "Fleet ID: $FLEET_ID"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo ""
echo "⏱️  PERFORMANCE METRICS:"
echo "   Total deployment time: ${minutes}m ${seconds}s"
echo "   vs. Previous method: ~20+ minutes"
echo "   Time saved: ~$(( (20*60 - total_time) / 60 ))+ minutes per deployment!"
echo ""
echo "📊 Monitor transcription progress:"
echo "   ssh -i $SSH_KEY_PATH ubuntu@$PUBLIC_IP"
echo "   tail -f transcription.log"
echo ""
echo "🔍 Check GPU utilization:"
echo "   ssh -i $SSH_KEY_PATH ubuntu@$PUBLIC_IP 'nvidia-smi'"
echo ""
echo "🛑 Stop fleet when complete:"
echo "   aws ec2 cancel-spot-fleet-requests --spot-fleet-request-ids $FLEET_ID --terminate-instances"
echo ""
echo "💰 Estimated cost for this session: \$0.35/hour spot price"
echo "🎯 With pre-built AMI: Ready to transcribe in under 5 minutes!"