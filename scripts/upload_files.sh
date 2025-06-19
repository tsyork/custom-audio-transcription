#!/bin/bash

# Helper script to upload audio files to GCS
echo "📤 Uploading audio files to GCS..."

if [ $# -eq 0 ]; then
    echo "Usage: ./upload_files.sh file1.m4a file2.m4a file3.m4a"
    echo "Or: ./upload_files.sh *.m4a"
    exit 1
fi

# Create bucket if it doesn't exist
gsutil mb -p podcast-transcription-462218 gs://custom-transcription 2>/dev/null || echo "Bucket already exists"

# Upload each file
for file in "$@"; do
    if [ -f "$file" ]; then
        echo "Uploading: $file"
        gsutil cp "$file" gs://custom-transcription/audio_files/
    else
        echo "File not found: $file"
    fi
done

echo "✅ Upload complete!"
echo "📁 Files uploaded to: gs://custom-transcription/audio_files/"
echo ""
echo "🚀 Ready to deploy! Run:"
echo "   cd scripts"
echo "   ./deploy_custom.sh"
