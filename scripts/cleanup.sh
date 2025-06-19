#!/bin/bash

# Cleanup AWS resources
if [ $# -eq 0 ]; then
    echo "Usage: ./cleanup.sh FLEET_ID"
    echo "Or: ./cleanup.sh"
    echo "   (will try to find latest fleet ID from logs)"
    exit 1
fi

if [ $# -eq 1 ]; then
    FLEET_ID="$1"
else
    # Try to find latest fleet ID from logs
    LATEST_FLEET_FILE=$(ls -t ../logs/fleet_id_* 2>/dev/null | head -1)
    if [ -n "$LATEST_FLEET_FILE" ]; then
        FLEET_ID=$(cat "$LATEST_FLEET_FILE")
        echo "Using Fleet ID from $LATEST_FLEET_FILE: $FLEET_ID"
    else
        echo "❌ No Fleet ID found in logs. Please provide Fleet ID manually."
        exit 1
    fi
fi

echo "🛑 Stopping AWS Spot Fleet: $FLEET_ID"
aws ec2 cancel-spot-fleet-requests --spot-fleet-request-ids $FLEET_ID --terminate-instances

echo "✅ Cleanup complete!"
echo "💰 Check your AWS billing to see final costs"
