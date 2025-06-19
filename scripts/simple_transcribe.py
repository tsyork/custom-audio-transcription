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
