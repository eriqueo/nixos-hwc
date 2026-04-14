#!/usr/bin/env python3
"""
Tdarr Auto-Configuration Script
Automatically sets up Tdarr to process large remux files (>20GB)
Safe mode: Creates new files, never touches originals
"""

import json
import sys
import subprocess
from pathlib import Path

# Tdarr configuration
TDARR_URL = "http://localhost:8265"

# Configuration
MOVIES_PATH = "/media/movies"
TV_PATH = "/media/tv"
TEMP_PATH = "/temp"
MIN_FILE_SIZE_GB = 20  # Only process files larger than this

def check_tdarr_running():
    """Check if Tdarr is accessible"""
    try:
        result = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:8265"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.stdout == "200":
            print("✅ Tdarr is running")
            return True
    except:
        pass
    print("❌ Tdarr is not accessible at http://localhost:8265")
    print("   Run: systemctl status podman-tdarr")
    return False

def create_library_config(library_name, source_path, description):
    """Create a Tdarr library configuration"""
    config = {
        "name": library_name,
        "source": source_path,
        "cache": TEMP_PATH,
        "output": source_path,  # Same as source = replace mode (but we'll use non-destructive flow)
        "folderWatch": True,
        "scanOnSave": True,
        "scanButtons": True,
        "priorityFilter": {
            "sortBy": "size",
            "sortOrder": "desc"  # Process largest files first
        },
        "filters": {
            "minFileSize": MIN_FILE_SIZE_GB * 1024 * 1024 * 1024,  # Convert to bytes
        },
        "description": description
    }
    return config

def create_remux_flow():
    """
    Create a transcoding flow for large remux files

    This flow will:
    1. Filter files > 20GB
    2. Check if already H.265
    3. Transcode to H.265 using NVENC (GPU)
    4. Keep audio streams (no re-encode)
    5. Output to /temp for manual verification
    """
    flow = {
        "name": "Large Remux Optimizer",
        "description": "Compress huge remux files (>20GB) using H.265 NVENC",
        "isEnabled": True,
        "plugins": [
            {
                # Plugin 1: Filter by file size
                "name": "Filter by File Size",
                "pluginId": "filterByFileSize",
                "position": 1,
                "settings": {
                    "minSize": MIN_FILE_SIZE_GB * 1024,  # In MB
                    "action": "continue"
                }
            },
            {
                # Plugin 2: Skip if already H.265
                "name": "Skip if H.265",
                "pluginId": "checkVideoCodec",
                "position": 2,
                "settings": {
                    "codec": "hevc",
                    "action": "skip_if_match"
                }
            },
            {
                # Plugin 3: Transcode to H.265 (NVENC)
                "name": "Transcode to H.265 NVENC",
                "pluginId": "ffmpegCommand",
                "position": 3,
                "settings": {
                    "command": "-c:v hevc_nvenc -preset slow -crf 22 -c:a copy -c:s copy",
                    "container": ".mkv",
                    "outputFolder": f"{TEMP_PATH}/transcoded"
                }
            },
            {
                # Plugin 4: Verify output
                "name": "Validate Transcode",
                "pluginId": "validateMediaStream",
                "position": 4,
                "settings": {
                    "checkDuration": True,
                    "maxDurationDiff": 2  # seconds
                }
            }
        ]
    }
    return flow

def print_manual_setup_guide():
    """Print step-by-step manual setup instructions"""
    print("\n" + "="*70)
    print("📋 TDARR MANUAL SETUP GUIDE")
    print("="*70)

    print("\n🌐 Step 1: Open Tdarr Web UI")
    print("   URL: http://localhost:8265")
    print("   (If on remote machine, use SSH tunnel or tailscale)")

    print("\n📚 Step 2: Add Movies Library")
    print("   1. Click 'Libraries' tab")
    print("   2. Click '+ Library' button")
    print("   3. Fill in:")
    print(f"      - Name: Big Movies")
    print(f"      - Source: {MOVIES_PATH}")
    print(f"      - Cache: {TEMP_PATH}")
    print(f"      - Output: {TEMP_PATH}/transcoded")
    print("      - Folder Watch: ✓ Enable")
    print("      - Scan on Save: ✓ Enable")
    print("   4. Click 'Save'")

    print("\n📺 Step 3: Add TV Library (Optional)")
    print("   Same steps as above, but:")
    print(f"      - Name: Big TV Shows")
    print(f"      - Source: {TV_PATH}")

    print("\n⚙️ Step 4: Create Transcoding Flow")
    print("   1. Click 'Flows' tab")
    print("   2. Click '+ Flow' button")
    print("   3. Name: 'Remux Compressor'")
    print("   4. Add these plugins in order:")
    print()
    print("   🔹 Plugin 1: Filter File Size")
    print("      - Search: 'Community: Check Size'")
    print("      - Min Size: 20000 MB (20GB)")
    print("      - Action: Continue if larger")
    print()
    print("   🔹 Plugin 2: Check Video Codec")
    print("      - Search: 'Community: Check Video Codec'")
    print("      - Target Codec: hevc (H.265)")
    print("      - Action: Skip if already H.265")
    print()
    print("   🔹 Plugin 3: Transcode Customized")
    print("      - Search: 'Community: Transcode Customized'")
    print("      - FFmpeg Options:")
    print("        -c:v hevc_nvenc -preset slow -crf 22 -c:a copy -c:s copy")
    print("      - Container: .mkv")
    print("      - Output Path: /temp/transcoded")
    print()
    print("   🔹 Plugin 4: Replace Original (DISABLE FOR NOW)")
    print("      - Search: 'Community: Replace Original'")
    print("      - DISABLED (test manually first!)")

    print("\n🎯 Step 5: Assign Flow to Library")
    print("   1. Go back to 'Libraries' tab")
    print("   2. Click on 'Big Movies'")
    print("   3. Scroll to 'Transcode Options'")
    print("   4. Select Flow: 'Remux Compressor'")
    print("   5. Click 'Save'")

    print("\n▶️ Step 6: Start Processing")
    print("   1. Click 'Staging' tab")
    print("   2. Click 'Scan All Libraries'")
    print("   3. Wait 5-10 minutes for scan")
    print("   4. Files > 20GB will appear in queue")
    print("   5. Processing starts automatically")

    print("\n📊 Step 7: Monitor Progress")
    print("   - 'Staging' tab: See current jobs")
    print("   - 'Files' tab: See completed/failed")
    print("   - Check /mnt/hot/processing/tdarr-temp/transcoded/ for output files")

    print("\n✅ Step 8: Verify Quality")
    print("   1. After first file completes:")
    print("      Original: /mnt/media/movies/Ghost in the Shell 2.../")
    print("      Transcoded: /mnt/hot/processing/tdarr-temp/transcoded/")
    print("   2. Play both files side-by-side")
    print("   3. Compare quality, check audio sync")
    print("   4. Check file size reduction (should be 50-70% smaller)")

    print("\n🎬 Expected Results:")
    print("   - Ghost in the Shell 2 (72GB) → ~25GB")
    print("   - Ghost in the Shell (51GB) → ~18GB")
    print("   - Fantasia (36GB) → ~13GB")
    print("   - Processing time: 2-4 hours per movie (with GPU)")

    print("\n⚠️ IMPORTANT SAFETY NOTES:")
    print("   - Originals are NEVER touched (files go to /temp/transcoded)")
    print("   - Manually verify quality before replacing originals")
    print("   - Keep transcoded files for 1-2 weeks before deleting originals")
    print("   - Test on 2-3 movies first before processing everything")

    print("\n🔧 Troubleshooting:")
    print("   - No files in queue? Check file size filter (must be >20GB)")
    print("   - Processing stuck? Check logs in 'Logs' tab")
    print("   - GPU not working? Verify: nvidia-smi shows Tdarr process")
    print("   - Worker disconnecting? Restart: systemctl restart podman-tdarr")

    print("\n" + "="*70)
    print("📚 For more details, see:")
    print("   /home/eric/.nixos/domains/server/containers/tdarr/README.md")
    print("="*70 + "\n")

def main():
    print("🎬 Tdarr Auto-Configuration Tool")
    print("="*70)

    # Check if Tdarr is running
    if not check_tdarr_running():
        sys.exit(1)

    print("\n📝 This script will show you how to configure Tdarr to:")
    print(f"   - Process files larger than {MIN_FILE_SIZE_GB}GB")
    print("   - Convert to H.265 using GPU (NVENC)")
    print("   - Save 50-70% storage space")
    print("   - Keep originals safe (non-destructive mode)")

    print("\n⚠️  NOTE: Tdarr doesn't have a robust API for automation.")
    print("   You'll need to configure it manually via the web UI.")
    print("   But don't worry - I'll guide you through every step!")

    input("\nPress ENTER to see the step-by-step guide...")

    print_manual_setup_guide()

    # Create example configurations as reference
    print("\n💾 Creating example configuration files for reference...")

    config_dir = Path("/home/eric/.nixos/workspace/media/config-examples/tdarr")
    config_dir.mkdir(parents=True, exist_ok=True)

    # Save library config example
    movies_lib = create_library_config("Big Movies", MOVIES_PATH, "Movies larger than 20GB")
    with open(config_dir / "library-movies-example.json", "w") as f:
        json.dump(movies_lib, f, indent=2)

    tv_lib = create_library_config("Big TV Shows", TV_PATH, "TV shows with large episodes")
    with open(config_dir / "library-tv-example.json", "w") as f:
        json.dump(tv_lib, f, indent=2)

    # Save flow config example
    flow = create_remux_flow()
    with open(config_dir / "flow-remux-optimizer.json", "w") as f:
        json.dump(flow, f, indent=2)

    print(f"   ✅ Saved to: {config_dir}/")
    print("   (These are reference examples - Tdarr config is done via UI)")

    print("\n" + "="*70)
    print("✨ Setup guide complete!")
    print("   Next: Open http://localhost:8265 and follow the steps above")
    print("="*70 + "\n")

if __name__ == "__main__":
    main()
