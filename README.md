# Custom Audio Transcription

🎙️ **AWS Spot Fleet transcription system for custom audio files using OpenAI Whisper**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-EC2%20Spot%20Fleet-orange)](https://aws.amazon.com/ec2/spot/)
[![Google Cloud](https://img.shields.io/badge/Google%20Cloud-Storage%20%7C%20Drive-blue)](https://cloud.google.com/)
[![OpenAI Whisper](https://img.shields.io/badge/OpenAI-Whisper-green)](https://openai.com/research/whisper)

## 🎯 Overview

High-performance, cost-efficient transcription system that leverages AWS Spot Fleet instances with GPU acceleration to transcribe audio files 8-10x faster than local processing, at 90% cost savings compared to on-demand instances.

### Key Features

- **⚡ GPU-Accelerated**: 8-10x faster transcription using NVIDIA T4 GPUs
- **💰 Cost-Efficient**: ~$0.75 for 7 hours of audio using spot instances
- **🤖 AI-Powered**: OpenAI Whisper for high-quality transcription
- **☁️ Cloud-Native**: Google Cloud Storage + Google Drive integration
- **🚀 One-Command Deploy**: Fully automated setup and processing
- **🔒 Secure**: No credentials stored in repository
- **📱 Auto-Shutdown**: Prevents accidental billing charges

## 📊 Performance

| Metric | Local Processing | This System |
|--------|------------------|-------------|
| **7 hours audio** | ~14 hours processing | ~3.5 hours processing |
| **Cost** | Electricity + time | ~$0.75 total |
| **Quality** | Depends on hardware | Consistent GPU performance |
| **Scalability** | Limited by local resources | Unlimited cloud scaling |

## 🏗️ Architecture

```
Audio Files (GCS) → AWS Spot Fleet (GPU) → Whisper Transcription → Google Docs
                                    ↓
                            Metadata Storage (GCS)
```

**Infrastructure:**
- **Compute**: AWS g4dn.xlarge spot instances with NVIDIA T4 GPU
- **Storage**: Google Cloud Storage for audio files and metadata
- **Output**: Google Drive documents with formatted transcripts
- **Management**: Automated deployment, monitoring, and cleanup

## 🚀 Quick Start

### Prerequisites

- AWS account with programmatic access
- Google Cloud project with APIs enabled
- Audio files in .m4a format

### 1. Clone and Setup

```bash
git clone https://github.com/YOUR_USERNAME/custom-audio-transcription.git
cd custom-audio-transcription
```

### 2. Configure Credentials

Follow the [Security Setup Guide](SECURITY_SETUP.md) to configure:
- AWS CLI authentication
- Google Cloud service account
- AWS SSH key pair
- Spot fleet configuration

### 3. Upload Audio Files

```bash
cd scripts
./upload_files.sh /path/to/your_audio_files/*.m4a
```

### 4. Deploy and Transcribe

```bash
./deploy_custom.sh
```

**That's it!** The system will:
- ✅ Launch AWS Spot Fleet automatically
- ✅ Set up GPU instance with all dependencies
- ✅ Download and transcribe your audio files
- ✅ Create formatted Google Docs
- ✅ Auto-shutdown when complete

## 📁 Project Structure

```
custom-audio-transcription/
├── scripts/                    # Core transcription scripts
│   ├── simple_transcribe.py    # Main transcription engine
│   ├── deploy_custom.sh        # One-command deployment
│   ├── upload_files.sh         # Audio file upload utility
│   ├── monitor_progress.sh     # Progress monitoring
│   └── cleanup.sh              # Resource cleanup
├── config/                     # Configuration files (gitignored)
│   ├── credentials.json        # Google Cloud service account
│   ├── spot-fleet-config.json  # AWS Spot Fleet settings
│   └── *.pem                   # SSH keys
├── logs/                       # Runtime logs (gitignored)
├── docs/                       # Documentation
├── SECURITY_SETUP.md           # Credential configuration guide
└── README.md                   # This file
```

## 🛠️ Customization

### Change Whisper Model

Edit `scripts/simple_transcribe.py`:
```python
WHISPER_MODEL = "large-v3"  # Best quality (slower)
WHISPER_MODEL = "medium"    # Balanced (default)
WHISPER_MODEL = "small"     # Fastest (lower quality)
```

### Add More Audio Formats

Extend the file detection logic:
```python
if blob.name.endswith(('.m4a', '.mp3', '.wav', '.flac')):
```

### Modify Output Format

Customize the Google Doc formatting in the `create_google_doc()` function.

## 🔧 Scripts Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy_custom.sh` | One-command deployment | `./deploy_custom.sh` |
| `upload_files.sh` | Upload audio to GCS | `./upload_files.sh *.m4a` |
| `monitor_progress.sh` | Monitor transcription | `./monitor_progress.sh [IP]` |
| `cleanup.sh` | Stop AWS resources | `./cleanup.sh [FLEET_ID]` |
| `simple_transcribe.py` | Main transcription logic | Auto-executed |

## 🔍 Monitoring

### Check Upload Status
```bash
gsutil ls gs://custom-transcription/audio_files/
```

### Monitor Instance Progress
```bash
# Auto-connect to latest instance
./monitor_progress.sh

# Or specify IP manually
./monitor_progress.sh 1.2.3.4
```

### View GPU Usage
```bash
# On the instance
nvidia-smi
```

## 🛡️ Security

- **No credentials stored in repository** - See [Security Setup Guide](SECURITY_SETUP.md)
- **All sensitive files are gitignored**
- **Template files provided for configuration**
- **Best practices documentation included**

## 💰 Cost Optimization

- **Spot instances**: 90% savings vs on-demand
- **Auto-shutdown**: Prevents accidental charges
- **GPU optimization**: Faster processing = lower costs
- **Pay-per-use**: Only pay for actual processing time

## 🔄 Scaling

### Process More Files
```bash
# Add more files anytime
./upload_files.sh additional_files/*.m4a
./deploy_custom.sh  # Will process only new files
```

### Multiple Concurrent Jobs
- Launch multiple spot fleets for parallel processing
- Each deployment creates isolated resources
- Logs track all fleet IDs for easy cleanup

## 📚 Use Cases

- **Podcast Transcription**: High-quality transcripts for content creators
- **Meeting Notes**: Convert recorded meetings to searchable documents
- **Interview Processing**: Transcribe research interviews or journalism
- **Content Creation**: Generate transcripts for video content
- **Accessibility**: Create text versions of audio content

## 🆘 Troubleshooting

### Common Issues

| Error | Solution |
|-------|----------|
| `gsutil: command not found` | Install Google Cloud SDK |
| `No audio files found` | Upload files with `upload_files.sh` |
| `AccessDenied` AWS error | Check AWS CLI configuration |
| `Permission denied` SSH | Fix key permissions: `chmod 400 *.pem` |

### Getting Help

1. Check the [Security Setup Guide](SECURITY_SETUP.md)
2. Verify all prerequisites are installed
3. Ensure credentials are properly configured
4. Monitor AWS instance logs for specific errors

## 🚀 Future Enhancements

- [ ] Support for additional audio formats
- [ ] Batch processing from local directories  
- [ ] Integration with other cloud storage providers
- [ ] Speaker diarization capabilities
- [ ] Multi-language detection
- [ ] Custom prompt templates
- [ ] Web interface for non-technical users
- [ ] API endpoints for programmatic access

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## ⭐ Acknowledgments

- **OpenAI Whisper** for state-of-the-art speech recognition
- **AWS Spot Fleet** for cost-effective GPU compute
- **Google Cloud Platform** for reliable storage and document services

---

**Built with ❤️ for efficient, cost-effective audio transcription**