#!/bin/bash

# Monitor transcription progress
if [ $# -eq 0 ]; then
    echo "Usage: ./monitor_progress.sh PUBLIC_IP"
    echo "Or: ./monitor_progress.sh"
    echo "   (will try to find latest IP from logs)"
    exit 1
fi

if [ $# -eq 1 ]; then
    PUBLIC_IP="$1"
else
    # Try to find latest IP from logs
    LATEST_IP_FILE=$(ls -t ../logs/instance_ip_* 2>/dev/null | head -1)
    if [ -n "$LATEST_IP_FILE" ]; then
        PUBLIC_IP=$(cat "$LATEST_IP_FILE")
        echo "Using IP from $LATEST_IP_FILE: $PUBLIC_IP"
    else
        echo "❌ No IP found in logs. Please provide IP manually."
        exit 1
    fi
fi

echo "🔍 Monitoring transcription progress..."
echo "Instance IP: $PUBLIC_IP"
echo ""
echo "Connecting to instance..."

ssh -i ../config/whisper-transcription-key.pem ubuntu@$PUBLIC_IP
