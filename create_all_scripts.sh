#!/bin/bash

# Generate All Scripts for Custom Audio Transcription Project
# Run this after setting up the project structure

set -e

PROJECT_DIR="$HOME/github/custom-audio-transcription"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found. Run setup_project_structure.sh first"
    exit 1
fi

cd "$PROJECT_DIR"

echo "🔧 Creating all project scripts..."

# ===== 1. MAIN TRANSCRIPTION SCRIPT =====
cat > scripts/simple_transcribe.py << 'EOF'
#!/usr/bin/env python3
"""
Streamlined Transcription Script for Custom Audio Files
Reuses AWS Spot Fleet infrastructure from podcast transcription project
"""

import os
import json
import time
import re
from pathlib import Path
from tqdm import tqdm
import whisper
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from google.cloud import storage
import certifi
import subprocess

os.environ['SSL_CERT_FILE'] = certifi.where()

# ===== CONFIGURATION =====
CREDENTIALS_FILE = "../config/credentials.json"
WHISPER_MODEL = "medium"  # Pre-configured for balance of speed/quality
TEMP_AUDIO_DIR = Path("./temp_audio")

# Google Cloud Storage Configuration (NEW BUCKET FOR YOUR FILES)
GCS_PROJECT_ID = "podcast-transcription-462218"
GCS_BUCKET_NAME = "custom-transcription"  # NEW: Separate bucket for your files
GCS_AUDIO_PREFIX = "audio_files/"  # Where your .m4a files are stored
GCS_METADATA_PREFIX = "metadata/"  # Where JSON metadata will be stored

# Google Drive Configuration (NEW FOLDER STRUCTURE)
ROOT_FOLDER_ID = "136Nmn3gJe0DPVh8p4vUl3oD4-qDNRySh"  # AI Transcripts folder
CUSTOM_FOLDER_NAME = "Custom Audio Transcripts"  # NEW: Separate folder for your files

SCOPES = [
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/cloud-platform"
]

# ===== AUTHENTICATION =====
def authenticate():
    """Authenticate with Google APIs and Cloud Storage"""
    creds = service_account.Credentials.from_service_account_file(
        CREDENTIALS_FILE, scopes=SCOPES)
    drive_service = build('drive', 'v3', credentials=creds)
    docs_service = build('docs', 'v1', credentials=creds)
    gcs_client = storage.Client(credentials=creds, project=GCS_PROJECT_ID)
    return drive_service, docs_service, gcs_client

# ===== SETUP FUNCTIONS =====
def setup_gcs_bucket(gcs_client):
    """Create GCS bucket if it doesn't exist"""
    try:
        bucket = gcs_client.get_bucket(GCS_BUCKET_NAME)
        print(f"✅ Using existing GCS bucket: {GCS_BUCKET_NAME}")
    except Exception:
        print(f"📦 Creating new GCS bucket: {GCS_BUCKET_NAME}")
        bucket = gcs_client.create_bucket(GCS_BUCKET_NAME)
    return bucket

def setup_drive_folder(drive_service):
    """Create or find the custom transcripts folder in Google Drive"""
    # Search for existing folder
    query = f"name='{CUSTOM_FOLDER_NAME}' and parents='{ROOT_FOLDER_ID}' and mimeType='application/vnd.google-apps.folder'"
    results = drive_service.files().list(q=query).execute()
    
    if results['files']:
        folder_id = results['files'][0]['id']
        print(f"✅ Using existing folder: {CUSTOM_FOLDER_NAME}")
    else:
        print(f"📁 Creating new folder: {CUSTOM_FOLDER_NAME}")
        folder_metadata = {
            'name': CUSTOM_FOLDER_NAME,
            'parents': [ROOT_FOLDER_ID],
            'mimeType': 'application/vnd.google-apps.folder'
        }
        folder = drive_service.files().create(body=folder_metadata).execute()
        folder_id = folder['id']
    
    return folder_id

# ===== AUDIO PROCESSING =====
def get_audio_files_from_gcs(gcs_client):
    """Get list of .m4a files from GCS bucket"""
    bucket = gcs_client.bucket(GCS_BUCKET_NAME)
    blobs = list(bucket.list_blobs(prefix=GCS_AUDIO_PREFIX))
    
    audio_files = []
    for blob in blobs:
        if blob.name.endswith('.m4a'):
            filename = Path(blob.name).name
            audio_files.append({
                'filename': filename,
                'gcs_path': blob.name,
                'size_mb': blob.size / (1024 * 1024)
            })
    
    return audio_files

def download_audio_file(gcs_client, gcs_path, local_path):
    """Download audio file from GCS to local temp directory"""
    bucket = gcs_client.bucket(GCS_BUCKET_NAME)
    blob = bucket.blob(gcs_path)
    
    # Ensure temp directory exists
    local_path.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"📥 Downloading {Path(gcs_path).name}...")
    blob.download_to_filename(str(local_path))
    return local_path

# ===== METADATA HANDLING =====
def load_metadata(gcs_client, filename):
    """Load existing metadata from GCS"""
    metadata_filename = f"{Path(filename).stem}.json"
    metadata_path = f"{GCS_METADATA_PREFIX}{metadata_filename}"
    
    try:
        bucket = gcs_client.bucket(GCS_BUCKET_NAME)
        blob = bucket.blob(metadata_path)
        metadata_json = blob.download_as_text()
        return json.loads(metadata_json)
    except Exception:
        # Create new metadata
        return {
            'filename': filename,
            'title': Path(filename).stem,
            'gcs_path': f"{GCS_AUDIO_PREFIX}{filename}",
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%S"),
            'status': 'pending'
        }

def save_metadata(gcs_client, metadata):
    """Save metadata to GCS"""
    metadata_filename = f"{Path(metadata['filename']).stem}.json"
    metadata_path = f"{GCS_METADATA_PREFIX}{metadata_filename}"
    
    bucket = gcs_client.bucket(GCS_BUCKET_NAME)
    blob = bucket.blob(metadata_path)
    blob.upload_from_string(json.dumps(metadata, indent=2))

# ===== GOOGLE DOCS CREATION =====
def create_google_doc(docs_service, drive_service, folder_id, metadata, transcript):
    """Create formatted Google Doc with transcript"""
    # Create document
    doc_title = f"{metadata['title']} - Transcript"
    doc = docs_service.documents().create(body={'title': doc_title}).execute()
    doc_id = doc['documentId']
    
    # Move to correct folder
    drive_service.files().update(
        fileId=doc_id,
        addParents=folder_id,
        removeParents='root'
    ).execute()
    
    # Format content
    header = f"""TRANSCRIPT: {metadata['title']}
Generated: {metadata.get('transcribed_at', 'Unknown')}
Model: {metadata.get('whisper_model', 'Unknown')}
Duration: {metadata.get('duration_minutes', 'Unknown'):.1f} minutes

{'='*50}

"""
    
    content = header + transcript
    
    # Insert content
    requests = [{
        'insertText': {
            'location': {'index': 1},
            'text': content
        }
    }]
    
    docs_service.documents().batchUpdate(
        documentId=doc_id,
        body={'requests': requests}
    ).execute()
    
    doc_url = f"https://docs.google.com/document/d/{doc_id}"
    print(f"📄 Created Google Doc: {doc_title}")
    print(f"🔗 URL: {doc_url}")
    
    return doc_id, doc_url

# ===== TRANSCRIPTION =====
def transcribe_audio(audio_path, metadata):
    """Transcribe audio file using Whisper"""
    print(f"🤖 Loading Whisper model: {WHISPER_MODEL}")
    model = whisper.load_model(WHISPER_MODEL)
    
    print(f"🎙️ Transcribing: {metadata['title']}")
    
    # Get duration
    audio = whisper.load_audio(str(audio_path))
    duration_seconds = len(audio) / whisper.audio.SAMPLE_RATE
    duration_minutes = duration_seconds / 60
    
    print(f"📏 Duration: {duration_minutes:.1f} minutes")
    print(f"⏱️ Estimated time: {duration_minutes * 0.5:.1f} minutes")
    
    # Transcribe with progress bar
    with tqdm(total=100, desc=f"🎙️ Transcribing", 
              bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]") as pbar:
        
        start_time = time.time()
        result = model.transcribe(str(audio_path), verbose=False)
        transcript = result["text"].strip()
        segments = result["segments"]
        pbar.update(100)
        
        elapsed_time = time.time() - start_time
        print(f"✅ Completed in {elapsed_time / 60:.1f} minutes")
    
    # Update metadata
    metadata.update({
        "transcript": transcript,
        "segments": segments,
        "whisper_model": WHISPER_MODEL,
        "transcribed_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "duration_minutes": duration_minutes,
        "processing_time_minutes": elapsed_time / 60,
        "status": "transcribed"
    })
    
    return transcript

# ===== AUTO SHUTDOWN =====
def shutdown_instance():
    """Shutdown the instance automatically"""
    print("💤 Auto-shutdown in 60 seconds... (Ctrl+C to cancel)")
    try:
        time.sleep(60)
        print("🔌 Shutting down instance...")
        subprocess.run(["sudo", "shutdown", "-h", "now"], check=True)
    except KeyboardInterrupt:
        print("❌ Auto-shutdown cancelled")

# ===== MAIN FUNCTION =====
def main():
    """Main transcription workflow"""
    print("🎙️ Custom Audio File Transcription")
    print("=" * 40)
    print(f"Model: {WHISPER_MODEL}")
    print(f"Expected files: .m4a files from GCS")
    print()
    
    # Authenticate
    print("🔐 Authenticating with Google Cloud...")
    drive_service, docs_service, gcs_client = authenticate()
    
    # Setup infrastructure
    print("🏗️ Setting up storage...")
    bucket = setup_gcs_bucket(gcs_client)
    folder_id = setup_drive_folder(drive_service)
    
    # Get audio files
    print("📂 Finding audio files...")
    audio_files = get_audio_files_from_gcs(gcs_client)
    
    if not audio_files:
        print("❌ No .m4a files found in GCS bucket!")
        print(f"📍 Upload your files to: gs://{GCS_BUCKET_NAME}/{GCS_AUDIO_PREFIX}")
        print("💡 Command: gsutil cp your_file.m4a gs://{GCS_BUCKET_NAME}/{GCS_AUDIO_PREFIX}")
        return
    
    print(f"✅ Found {len(audio_files)} audio files:")
    for i, file_info in enumerate(audio_files, 1):
        print(f"  {i}. {file_info['filename']} ({file_info['size_mb']:.1f} MB)")
    
    print(f"\n🚀 Starting transcription of {len(audio_files)} files...")
    
    # Create temp directory
    TEMP_AUDIO_DIR.mkdir(exist_ok=True)
    
    # Process each file
    completed = 0
    for i, file_info in enumerate(audio_files, 1):
        print(f"\n{'='*50}")
        print(f"📁 Processing file {i}/{len(audio_files)}: {file_info['filename']}")
        print(f"{'='*50}")
        
        try:
            # Load/create metadata
            metadata = load_metadata(gcs_client, file_info['filename'])
            
            # Check if already transcribed
            if metadata.get('status') == 'completed' and 'google_doc_url' in metadata:
                print(f"⏭️ Already transcribed: {metadata['google_doc_url']}")
                completed += 1
                continue
            
            # Download audio file
            temp_audio_path = TEMP_AUDIO_DIR / file_info['filename']
            download_audio_file(gcs_client, file_info['gcs_path'], temp_audio_path)
            
            # Transcribe
            transcript = transcribe_audio(temp_audio_path, metadata)
            
            # Create Google Doc
            doc_id, doc_url = create_google_doc(
                docs_service, drive_service, folder_id, metadata, transcript
            )
            
            # Update metadata with doc info
            metadata.update({
                'google_doc_id': doc_id,
                'google_doc_url': doc_url,
                'status': 'completed'
            })
            
            # Save metadata
            save_metadata(gcs_client, metadata)
            
            # Cleanup temp file
            temp_audio_path.unlink()
            
            completed += 1
            print(f"✅ File {i}/{len(audio_files)} completed")
            
        except Exception as e:
            print(f"❌ Error processing {file_info['filename']}: {e}")
            # Cleanup temp file if it exists
            temp_audio_path = TEMP_AUDIO_DIR / file_info['filename']
            if temp_audio_path.exists():
                temp_audio_path.unlink()
            continue
    
    # Final summary
    print(f"\n{'='*50}")
    print(f"🎉 TRANSCRIPTION COMPLETE")
    print(f"{'='*50}")
    print(f"✅ Successfully processed: {completed}/{len(audio_files)} files")
    print(f"📁 All transcripts saved to: {CUSTOM_FOLDER_NAME}")
    print(f"☁️ Metadata saved to: gs://{GCS_BUCKET_NAME}/{GCS_METADATA_PREFIX}")
    
    # Auto shutdown
    if completed > 0:
        shutdown_instance()

if __name__ == "__main__":
    main()
EOF

# ===== 2. DEPLOYMENT SCRIPT =====
cat > scripts/deploy_custom.sh << 'EOF'
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
EOF

# ===== 3. UPLOAD HELPER SCRIPT =====
cat > scripts/upload_files.sh << 'EOF'
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
EOF

# ===== 4. MONITORING SCRIPT =====
cat > scripts/monitor_progress.sh << 'EOF'
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
EOF

# ===== 5. CLEANUP SCRIPT =====
cat > scripts/cleanup.sh << 'EOF'
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
EOF

# Make all scripts executable
chmod +x scripts/*.sh
chmod +x scripts/*.py

echo ""
echo "✅ All scripts created successfully!"
echo ""
echo "📂 Scripts created in $PROJECT_DIR/scripts/:"
echo "   • simple_transcribe.py     - Main transcription script"
echo "   • deploy_custom.sh         - One-command deployment"
echo "   • upload_files.sh          - Audio file upload helper"
echo "   • monitor_progress.sh      - Progress monitoring"
echo "   • cleanup.sh               - Resource cleanup"
echo ""
echo "📋 Next steps:"
echo "1. Copy your config files to $PROJECT_DIR/config/"
echo "2. Upload audio files using upload_files.sh"
echo "3. Run deploy_custom.sh to start transcription"