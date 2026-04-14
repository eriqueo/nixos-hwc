# 🎬 Tdarr Quick Start Guide - Compress Your Huge Remux Files

**Problem**: You have 72GB Ghost in the Shell movies and 551GB of Star Trek TNG
**Solution**: Use Tdarr to compress them by 50-70% with no visible quality loss
**Time**: 2-4 hours per huge movie (with GPU acceleration)

---

## 🚀 Super Simple 8-Step Setup

### Step 1: Open Tdarr
```
http://localhost:8265
```
(Or use your tailscale URL if remote)

### Step 2: Add a Library
1. Click **"Libraries"** tab (top)
2. Click **"+ Library"** button
3. Fill in these EXACT values:

```
Name: Big Movies
Source: /media/movies
Cache: /temp
Output: /temp/transcoded
```

4. Enable these checkboxes:
   - ✅ **Folder watch**
   - ✅ **Scan on save**

5. Click **"Save"**

### Step 3: Create a Flow (The Magic Recipe)
1. Click **"Flows"** tab
2. Click **"+ Flow"** button
3. Name it: `Remux Compressor`
4. Now add 3 plugins:

#### Plugin A: Filter Big Files
- Search box: type `"check file size"`
- Find: **"Community: Check File Size"**
- Click **Add**
- Settings:
  - Min size: `20000` MB
  - Action: Continue

#### Plugin B: Skip if Already H.265
- Search: `"check video codec"`
- Find: **"Community: Check Video Codec"**
- Settings:
  - Target codec: `hevc` (or `h265`)
  - Action: Skip if already this codec

#### Plugin C: Transcode with GPU
- Search: `"transcode custom"`
- Find: **"Community: Transcode: Custom"**
- In the FFmpeg command box, paste this EXACTLY:
```
-c:v hevc_nvenc -preset slow -crf 22 -c:a copy -c:s copy
```
- Container: `.mkv`
- Output directory: `/temp/transcoded`

6. Click **"Save Flow"**

### Step 4: Connect Flow to Library
1. Go back to **"Libraries"** tab
2. Click on **"Big Movies"**
3. Scroll down to find **"Transcode Options"**
4. In the dropdown, select: `Remux Compressor`
5. Click **"Save"**

### Step 5: Start the Magic
1. Click **"Staging"** tab
2. Click **"Scan All Libraries"** button
3. Wait 5-10 minutes
4. Your huge files will appear in the list!

### Step 6: Watch It Work
- Look at the **"Staging"** tab to see what's processing
- Check **"Logs"** tab if something seems stuck
- Verify GPU is working: Run `nvidia-smi` in terminal

### Step 7: Check Results
After the first file finishes:
```bash
# Original (huge):
/mnt/media/movies/Ghost in the Shell 2.../movie.mkv (72GB)

# Compressed (much smaller):
/mnt/hot/processing/tdarr-temp/transcoded/Ghost in the Shell 2.../movie.mkv (~25GB)
```

**Play both files side by side** - you shouldn't see any quality difference!

### Step 8: Verify & Replace (IMPORTANT!)
⚠️ **DO NOT skip this step!**

1. Watch the compressed file completely
2. Check for:
   - Visual artifacts
   - Audio sync issues
   - Subtitle problems
3. If perfect after 2-3 movies, you can manually move them

---

## 📊 Expected Results

| Movie | Original | Compressed | Savings |
|-------|----------|------------|---------|
| Ghost in the Shell 2 | 72GB | ~25GB | 47GB |
| Ghost in the Shell | 51GB | ~18GB | 33GB |
| Fantasia | 36GB | ~13GB | 23GB |
| Being There | 27GB | ~10GB | 17GB |
| Citizen Kane | 26GB | ~9GB | 17GB |
| **TOTAL** | **212GB** | **~75GB** | **137GB saved!** |

---

## 🔧 Troubleshooting

**No files showing up?**
- Did you scan the library? (Staging → Scan All Libraries)
- Are your files actually >20GB? Check with: `du -sh /mnt/media/movies/*`

**Processing stuck/frozen?**
```bash
systemctl restart podman-tdarr
```

**GPU not being used?**
```bash
# While processing, run:
nvidia-smi

# You should see "tdarr" or "ffmpeg" in the process list
```

**Workers keep disconnecting?**
- This is normal - Tdarr recreates them as needed
- As long as files are processing, ignore it

**Want to process TV shows too?**
- Repeat Steps 2-4, but use `/media/tv` as the source
- Name it "Big TV Shows"

---

## ⚠️ SAFETY REMINDERS

✅ **What's Safe:**
- Tdarr creates NEW files in `/temp/transcoded`
- Your originals in `/media/movies` are NEVER touched
- You manually verify quality before deleting anything

❌ **Don't Do This:**
- Don't set Output to same as Source (yet)
- Don't enable "Replace Original" plugin (yet)
- Don't delete originals until you've verified quality

🎯 **Best Practice:**
1. Process 2-3 movies
2. Verify quality over 1-2 weeks
3. Only then move/replace originals
4. Keep originals for another week as backup

---

## 🎬 What This Actually Does

The magic command: `-c:v hevc_nvenc -preset slow -crf 22 -c:a copy -c:s copy`

- `hevc_nvenc` = Use NVIDIA GPU for H.265 encoding (fast!)
- `preset slow` = Better quality (still fast with GPU)
- `crf 22` = High quality (visually transparent)
- `-c:a copy` = Don't touch audio (keep original)
- `-c:s copy` = Keep subtitles exactly as-is

**Why H.265?**
- Same quality as H.264 at 40-50% smaller size
- Modern standard, plays everywhere
- Your GPU has hardware support for it

---

## 📞 Need Help?

**Run the setup script again:**
```bash
python3 ~/.nixos/workspace/utilities/scripts/setup-tdarr-auto.py
```

**Check the full safety guide:**
```bash
cat ~/.nixos/domains/server/containers/tdarr/README.md
```

**Check Tdarr status:**
```bash
systemctl status podman-tdarr
```

---

## 🏆 Success Checklist

After your first successful transcode:
- [ ] Original file still exists in `/media/movies`
- [ ] New file exists in `/temp/transcoded`
- [ ] New file is 40-70% smaller
- [ ] New file plays perfectly (no artifacts, good audio)
- [ ] GPU was used (check with `nvidia-smi`)
- [ ] File size savings match expectations

**If all checked ✅ = You're good to continue!**

---

**TL;DR:** Add library → Create flow → Scan → Wait → Verify quality → Profit! 🎉

Your 72GB Ghost in the Shell will become 25GB and look exactly the same!
