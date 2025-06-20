#!/bin/bash

# Check and recover from AMI creation timeout
AMI_ID="ami-037c68abef319a093"

echo "🔍 Checking status of AMI: $AMI_ID"

# Get current status
STATUS=$(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].State' --output text 2>/dev/null)
MESSAGE=$(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].StateReason.Message' --output text 2>/dev/null)

echo "Current Status: $STATUS"
if [ "$MESSAGE" != "None" ] && [ ! -z "$MESSAGE" ]; then
    echo "Status Message: $MESSAGE"
fi

case $STATUS in
    "available")
        echo "🎉 AMI is ready! The wait just timed out."
        echo "📝 Updating your spot-fleet-config.json..."
        
        # Create backup
        cp config/spot-fleet-config.json config/spot-fleet-config.json.backup
        
        # Update config
        python3 -c "
import json
with open('config/spot-fleet-config.json', 'r') as f:
    config = json.load(f)
config['LaunchSpecifications'][0]['ImageId'] = '$AMI_ID'
with open('config/spot-fleet-config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('✅ Updated config/spot-fleet-config.json with AMI: $AMI_ID')
"
        
        echo ""
        echo "🎯 AMI CREATION COMPLETE!"
        echo "========================"
        echo "AMI ID: $AMI_ID"
        echo "Updated: config/spot-fleet-config.json"
        echo "Backup: config/spot-fleet-config.json.backup"
        echo ""
        echo "🚀 You can now use fast deployment:"
        echo "./deploy-transcription-fast.sh"
        ;;
        
    "pending")
        echo "⏳ AMI is still being created. This can take 15-25 minutes total."
        echo "🔄 Continuing to wait..."
        echo "Press Ctrl+C to stop waiting and check manually later."
        
        # Continue waiting with progress updates
        while true; do
            sleep 60
            NEW_STATUS=$(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].State' --output text 2>/dev/null)
            echo "   Status: $NEW_STATUS ($(date +%H:%M:%S))"
            
            if [ "$NEW_STATUS" = "available" ]; then
                echo "🎉 AMI creation completed!"
                # Update config automatically
                cp config/spot-fleet-config.json config/spot-fleet-config.json.backup
                python3 -c "
import json
with open('config/spot-fleet-config.json', 'r') as f:
    config = json.load(f)
config['LaunchSpecifications'][0]['ImageId'] = '$AMI_ID'
with open('config/spot-fleet-config.json', 'w') as f:
    json.dump(config, f, indent=2)
print('✅ Updated config/spot-fleet-config.json with AMI: $AMI_ID')
"
                echo "🚀 Ready for fast deployment: ./deploy-transcription-fast.sh"
                break
            elif [ "$NEW_STATUS" = "failed" ] || [ "$NEW_STATUS" = "error" ]; then
                echo "❌ AMI creation failed!"
                aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].StateReason' --output table
                break
            fi
        done
        ;;
        
    "failed"|"error")
        echo "❌ AMI creation failed!"
        echo "Error details:"
        aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].StateReason' --output table
        echo ""
        echo "🔄 You can try creating the AMI again:"
        echo "./create-whisper-ami.sh"
        ;;
        
    *)
        echo "❓ Unknown status: $STATUS"
        echo "Full details:"
        aws ec2 describe-images --image-ids $AMI_ID --output table
        ;;
esac
