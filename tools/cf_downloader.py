#!/usr/bin/env python3
"""
CurseForge Mod Downloader
-------------------------
Downloads mods from manifest.json using unofficial CurseForge endpoints.
This script is part of the MinecraftServerInstall project.

Usage:
    python3 cf_downloader.py <manifest.json> [target_dir]

Features:
- Downloads mods from CurseForge using project/file IDs
- Fallback to latest compatible version on 404
- Comprehensive error handling and logging
- Resume capability for interrupted downloads
- Rate limiting and backoff for stability

WARNING: Uses unofficial endpoints that may change or have rate limits.
This feature is optional and experimental.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import argparse
import hashlib

class ModDownloader:
    def __init__(self, target_dir: str = "./mods", verbose: bool = False):
        self.target_dir = Path(target_dir)
        self.verbose = verbose
        self.downloaded = 0
        self.failed = 0
        self.skipped = 0
        self.failed_mods = []
        
        # Rate limiting
        self.request_delay = 1.0  # seconds between requests
        self.last_request = 0
        
        # Retry configuration
        self.max_retries = 3
        self.retry_delay = 2.0
        
        # User agent to appear as regular browser
        self.user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        
        self.target_dir.mkdir(parents=True, exist_ok=True)
        
    def log(self, message: str, force: bool = False):
        """Log message if verbose mode is enabled or force is True"""
        if self.verbose or force:
            print(f"[CF-DOWNLOADER] {message}")
    
    def log_error(self, message: str):
        """Always log error messages"""
        print(f"[CF-DOWNLOADER ERROR] {message}", file=sys.stderr)
    
    def rate_limit(self):
        """Enforce rate limiting between requests"""
        elapsed = time.time() - self.last_request
        if elapsed < self.request_delay:
            time.sleep(self.request_delay - elapsed)
        self.last_request = time.time()
    
    def make_request(self, url: str, timeout: int = 30) -> Optional[urllib.request.Response]:
        """Make HTTP request with retry logic and proper headers"""
        headers = {
            'User-Agent': self.user_agent,
            'Accept': 'application/json, text/html, */*',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
        }
        
        for attempt in range(self.max_retries):
            try:
                self.rate_limit()
                request = urllib.request.Request(url, headers=headers)
                response = urllib.request.urlopen(request, timeout=timeout)
                return response
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    return None  # File not found, don't retry
                elif e.code == 429:  # Rate limited
                    delay = (2 ** attempt) * self.retry_delay
                    self.log(f"Rate limited (429), waiting {delay:.1f}s before retry {attempt + 1}/{self.max_retries}")
                    time.sleep(delay)
                else:
                    self.log_error(f"HTTP {e.code} for {url}: {e.reason}")
                    if attempt == self.max_retries - 1:
                        return None
            except urllib.error.URLError as e:
                self.log_error(f"Network error for {url}: {e.reason}")
                if attempt == self.max_retries - 1:
                    return None
            except Exception as e:
                self.log_error(f"Unexpected error for {url}: {str(e)}")
                if attempt == self.max_retries - 1:
                    return None
            
            if attempt < self.max_retries - 1:
                delay = (2 ** attempt) * self.retry_delay
                self.log(f"Retrying in {delay:.1f}s... (attempt {attempt + 2}/{self.max_retries})")
                time.sleep(delay)
        
        return None
    
    def get_mod_metadata(self, project_id: int) -> Optional[Dict]:
        """Get mod metadata from CFWidget API"""
        try:
            url = f"https://api.cfwidget.com/{project_id}"
            self.log(f"Fetching metadata for project {project_id}")
            
            response = self.make_request(url)
            if not response:
                return None
            
            data = json.loads(response.read().decode('utf-8'))
            return data
        except Exception as e:
            self.log_error(f"Failed to get metadata for project {project_id}: {str(e)}")
            return None
    
    def download_mod_direct(self, project_id: int, file_id: int) -> Optional[Tuple[str, bytes]]:
        """Try direct download from CurseForge"""
        try:
            # Try the unofficial direct download endpoint
            url = f"https://www.curseforge.com/api/v1/mods/{project_id}/files/{file_id}/download"
            self.log(f"Attempting direct download: project={project_id}, file={file_id}")
            
            response = self.make_request(url)
            if not response:
                return None
            
            # Try to get filename from Content-Disposition header
            content_disposition = response.headers.get('Content-Disposition', '')
            filename = None
            if 'filename=' in content_disposition:
                filename = content_disposition.split('filename=')[-1].strip('"\'')
            
            # Fallback: generate filename from IDs
            if not filename:
                filename = f"mod-{project_id}-{file_id}.jar"
            
            # Ensure .jar extension
            if not filename.lower().endswith('.jar'):
                filename += '.jar'
            
            data = response.read()
            self.log(f"Successfully downloaded {filename} ({len(data)} bytes)")
            return filename, data
            
        except Exception as e:
            self.log_error(f"Direct download failed for {project_id}/{file_id}: {str(e)}")
            return None
    
    def download_mod_fallback(self, project_id: int, minecraft_version: str) -> Optional[Tuple[str, bytes]]:
        """Fallback: try to download latest compatible version"""
        try:
            self.log(f"Attempting fallback download for project {project_id} (MC {minecraft_version})")
            
            # Get mod metadata
            metadata = self.get_mod_metadata(project_id)
            if not metadata:
                return None
            
            mod_name = metadata.get('title', f'mod-{project_id}')
            self.log(f"Mod name: {mod_name}")
            
            # Look for compatible files
            files = metadata.get('files', {})
            compatible_files = []
            
            for version, file_list in files.items():
                if minecraft_version in version or version in minecraft_version:
                    compatible_files.extend(file_list)
            
            # If no version-specific match, try latest
            if not compatible_files and files:
                # Get the most recent version
                latest_version = max(files.keys()) if files else None
                if latest_version:
                    compatible_files = files[latest_version]
                    self.log(f"No exact version match, trying latest: {latest_version}")
            
            if not compatible_files:
                self.log_error(f"No compatible files found for {mod_name}")
                return None
            
            # Try to download the first compatible file
            for file_info in compatible_files[:3]:  # Try first 3 files
                if isinstance(file_info, dict) and 'id' in file_info:
                    file_id = file_info['id']
                    result = self.download_mod_direct(project_id, file_id)
                    if result:
                        filename, data = result
                        self.log(f"Fallback successful: {filename} for {mod_name}", force=True)
                        return filename, data
            
            return None
            
        except Exception as e:
            self.log_error(f"Fallback download failed for project {project_id}: {str(e)}")
            return None
    
    def download_mod(self, project_id: int, file_id: int, minecraft_version: str) -> bool:
        """Download a single mod with fallback logic"""
        try:
            # Check if already exists (simple filename pattern)
            existing_files = list(self.target_dir.glob(f"*{project_id}*{file_id}*.jar"))
            if existing_files:
                self.log(f"Mod {project_id}/{file_id} already exists: {existing_files[0].name}")
                self.skipped += 1
                return True
            
            # Try direct download first
            result = self.download_mod_direct(project_id, file_id)
            
            # If direct download fails, try fallback
            if not result:
                self.log(f"Direct download failed, attempting fallback for project {project_id}")
                result = self.download_mod_fallback(project_id, minecraft_version)
                
                if result:
                    self.log(f"⚠️  Using fallback version for project {project_id} (original file {file_id} not found)", force=True)
            
            if not result:
                self.log_error(f"All download attempts failed for project {project_id}, file {file_id}")
                self.failed += 1
                self.failed_mods.append((project_id, file_id, "Download failed"))
                return False
            
            filename, data = result
            
            # Sanitize filename
            safe_filename = "".join(c for c in filename if c.isalnum() or c in ".-_").strip()
            if not safe_filename.endswith('.jar'):
                safe_filename += '.jar'
            
            # Add project/file ID to filename for tracking
            name_parts = safe_filename.rsplit('.jar', 1)
            safe_filename = f"{name_parts[0]}-{project_id}-{file_id}.jar"
            
            target_path = self.target_dir / safe_filename
            
            # Write file
            with open(target_path, 'wb') as f:
                f.write(data)
            
            self.log(f"✅ Downloaded: {safe_filename} ({len(data)} bytes)", force=True)
            self.downloaded += 1
            return True
            
        except Exception as e:
            self.log_error(f"Failed to download mod {project_id}/{file_id}: {str(e)}")
            self.failed += 1
            self.failed_mods.append((project_id, file_id, str(e)))
            return False
    
    def download_from_manifest(self, manifest_path: str) -> bool:
        """Download all mods from a CurseForge manifest.json"""
        try:
            with open(manifest_path, 'r', encoding='utf-8') as f:
                manifest = json.load(f)
            
            minecraft_version = manifest.get('minecraft', {}).get('version', '1.20.1')
            mods = manifest.get('files', [])
            
            self.log(f"Found {len(mods)} mods in manifest for Minecraft {minecraft_version}", force=True)
            
            if not mods:
                self.log("No mods found in manifest", force=True)
                return True
            
            # Process each mod
            for i, mod in enumerate(mods, 1):
                project_id = mod.get('projectID')
                file_id = mod.get('fileID')
                
                if not project_id or not file_id:
                    self.log_error(f"Invalid mod entry #{i}: missing projectID or fileID")
                    self.failed += 1
                    continue
                
                self.log(f"[{i}/{len(mods)}] Processing mod {project_id}/{file_id}")
                self.download_mod(project_id, file_id, minecraft_version)
                
                # Progress update every 10 mods
                if i % 10 == 0:
                    self.log(f"Progress: {i}/{len(mods)} processed (✅{self.downloaded} ⏭️{self.skipped} ❌{self.failed})", force=True)
            
            return True
            
        except FileNotFoundError:
            self.log_error(f"Manifest file not found: {manifest_path}")
            return False
        except json.JSONDecodeError as e:
            self.log_error(f"Invalid JSON in manifest: {str(e)}")
            return False
        except Exception as e:
            self.log_error(f"Failed to process manifest: {str(e)}")
            return False
    
    def write_missing_mods_log(self, log_dir: str = "logs"):
        """Write failed downloads to missing-mods.txt"""
        if not self.failed_mods:
            return
        
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "missing-mods.txt")
        
        with open(log_path, 'w', encoding='utf-8') as f:
            f.write(f"# Missing Mods Report - {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# Total failed: {len(self.failed_mods)}\n\n")
            
            for project_id, file_id, reason in self.failed_mods:
                f.write(f"ProjectID: {project_id}, FileID: {file_id}\n")
                f.write(f"Reason: {reason}\n")
                f.write(f"Manual download: https://www.curseforge.com/minecraft/mc-mods/project/{project_id}\n")
                f.write("\n")
        
        self.log(f"Missing mods logged to: {log_path}", force=True)
    
    def print_summary(self):
        """Print download summary"""
        total = self.downloaded + self.skipped + self.failed
        print(f"\n🎯 Download Summary:")
        print(f"   Total mods: {total}")
        print(f"   ✅ Downloaded: {self.downloaded}")
        print(f"   ⏭️  Skipped (already exist): {self.skipped}")
        print(f"   ❌ Failed: {self.failed}")
        
        if self.failed > 0:
            print(f"\n⚠️  {self.failed} mods failed to download. Check logs/missing-mods.txt")
            success_rate = (self.downloaded / total * 100) if total > 0 else 0
            print(f"   Success rate: {success_rate:.1f}%")
        else:
            print("   🎉 All mods downloaded successfully!")


def main():
    parser = argparse.ArgumentParser(description='Download mods from CurseForge manifest.json')
    parser.add_argument('manifest', help='Path to manifest.json file')
    parser.add_argument('target_dir', nargs='?', default='./mods', help='Target directory for mods (default: ./mods)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose logging')
    parser.add_argument('--delay', type=float, default=1.0, help='Delay between requests in seconds (default: 1.0)')
    
    args = parser.parse_args()
    
    # Validate manifest file
    if not os.path.isfile(args.manifest):
        print(f"Error: Manifest file not found: {args.manifest}", file=sys.stderr)
        return 1
    
    # Create downloader
    downloader = ModDownloader(args.target_dir, args.verbose)
    downloader.request_delay = args.delay
    
    print(f"🚀 Starting mod download from {args.manifest}")
    print(f"   Target directory: {Path(args.target_dir).absolute()}")
    print(f"   Request delay: {args.delay}s")
    if args.verbose:
        print("   Verbose logging: enabled")
    print()
    
    # Download mods
    start_time = time.time()
    success = downloader.download_from_manifest(args.manifest)
    duration = time.time() - start_time
    
    # Write missing mods log
    downloader.write_missing_mods_log()
    
    # Print summary
    downloader.print_summary()
    print(f"\n⏱️  Total time: {duration:.1f}s")
    
    # Return appropriate exit code
    if not success:
        return 2  # Manifest/parsing error
    elif downloader.failed > 0:
        return 1  # Some downloads failed
    else:
        return 0  # All successful


if __name__ == '__main__':
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\n⚠️  Download interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"Fatal error: {str(e)}", file=sys.stderr)
        sys.exit(3)