#!/usr/bin/env python3
"""
Robust Download Manager for Minecraft Server Setup
=================================================

This Python tool provides robust download functionality with:
- Retry logic with exponential backoff
- Progress bars for large downloads
- Checksum verification (MD5, SHA1, SHA256)
- Multi-threaded downloads for performance
- Graceful error handling and logging
- Resume capability for interrupted downloads

Usage:
    python3 download_manager.py <command> [options]

Commands:
    download <url> <output>        - Download file from URL
    batch-download <urls_file>     - Download multiple files from list
    verify <file> <checksum>       - Verify file checksum
    get-info <url>                 - Get download information without downloading

Examples:
    # Simple download
    python3 download_manager.py download https://example.com/file.jar server.jar
    
    # Download with checksum verification
    python3 download_manager.py download --verify-sha256=abc123 https://example.com/file.jar server.jar
    
    # Batch download from file list
    python3 download_manager.py batch-download downloads.txt
"""

import sys
import os
import argparse
import logging
import hashlib
import time
import threading
from pathlib import Path
from typing import Optional, Dict, List, Tuple, Callable
from dataclasses import dataclass
from urllib.parse import urlparse, urljoin
from urllib.request import urlopen, Request
from urllib.error import HTTPError, URLError
import json
import tempfile
import shutil


# =============================================================================
# DOWNLOAD CONFIGURATION AND TYPES
# =============================================================================

@dataclass
class DownloadConfig:
    """Configuration for download operations"""
    max_retries: int = 3
    retry_delay: float = 1.0  # Initial delay in seconds
    retry_backoff: float = 2.0  # Multiplier for delay between retries
    timeout: int = 30  # Timeout in seconds
    chunk_size: int = 8192  # Download chunk size
    show_progress: bool = True
    verify_ssl: bool = True
    user_agent: str = "MinecraftServerSetup/1.0 (Download Manager)"
    max_parallel: int = 4  # Max parallel downloads for batch operations


@dataclass
class DownloadResult:
    """Result of a download operation"""
    success: bool
    file_path: Optional[Path] = None
    error_message: Optional[str] = None
    file_size: int = 0
    download_time: float = 0.0
    checksum_verified: bool = False
    checksum_value: Optional[str] = None


class DownloadError(Exception):
    """Custom exception for download errors"""
    pass


# =============================================================================
# PROGRESS REPORTING
# =============================================================================

class ProgressReporter:
    """Thread-safe progress reporting for downloads"""
    
    def __init__(self, total_size: int = 0, show_progress: bool = True):
        self.total_size = total_size
        self.downloaded = 0
        self.show_progress = show_progress
        self.start_time = time.time()
        self.lock = threading.Lock()
        self.last_update = 0
        
    def update(self, chunk_size: int):
        """Update progress with downloaded bytes"""
        with self.lock:
            self.downloaded += chunk_size
            current_time = time.time()
            
            # Update display at most once per second
            if not self.show_progress or current_time - self.last_update < 1.0:
                return
                
            self.last_update = current_time
            self._display_progress()
    
    def _display_progress(self):
        """Display current progress"""
        if self.total_size > 0:
            percentage = (self.downloaded / self.total_size) * 100
            downloaded_mb = self.downloaded / (1024 * 1024)
            total_mb = self.total_size / (1024 * 1024)
            
            # Calculate speed
            elapsed = time.time() - self.start_time
            if elapsed > 0:
                speed_mbps = downloaded_mb / elapsed
                eta = (total_mb - downloaded_mb) / speed_mbps if speed_mbps > 0 else 0
                
                print(f"\rProgress: {percentage:.1f}% ({downloaded_mb:.1f}/{total_mb:.1f} MB) "
                      f"Speed: {speed_mbps:.1f} MB/s ETA: {eta:.0f}s", end="", flush=True)
            else:
                print(f"\rProgress: {percentage:.1f}% ({downloaded_mb:.1f}/{total_mb:.1f} MB)", 
                      end="", flush=True)
        else:
            downloaded_mb = self.downloaded / (1024 * 1024)
            elapsed = time.time() - self.start_time
            speed_mbps = downloaded_mb / elapsed if elapsed > 0 else 0
            print(f"\rDownloaded: {downloaded_mb:.1f} MB Speed: {speed_mbps:.1f} MB/s", 
                  end="", flush=True)
    
    def finish(self):
        """Complete progress reporting"""
        if self.show_progress:
            print()  # New line after progress


# =============================================================================
# CHECKSUM VERIFICATION
# =============================================================================

class ChecksumVerifier:
    """Handles file checksum verification"""
    
    ALGORITHMS = {
        'md5': hashlib.md5,
        'sha1': hashlib.sha1,
        'sha256': hashlib.sha256,
        'sha512': hashlib.sha512,
    }
    
    @classmethod
    def verify_file(cls, file_path: Path, expected_checksum: str, algorithm: str = 'sha256') -> bool:
        """Verify file checksum"""
        algorithm = algorithm.lower()
        
        if algorithm not in cls.ALGORITHMS:
            raise ValueError(f"Unsupported checksum algorithm: {algorithm}")
        
        if not file_path.exists():
            return False
        
        try:
            hash_obj = cls.ALGORITHMS[algorithm]()
            
            with open(file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(8192), b''):
                    hash_obj.update(chunk)
            
            calculated_checksum = hash_obj.hexdigest()
            return calculated_checksum.lower() == expected_checksum.lower()
            
        except Exception as e:
            logging.error(f"Error verifying checksum: {e}")
            return False
    
    @classmethod
    def calculate_checksum(cls, file_path: Path, algorithm: str = 'sha256') -> Optional[str]:
        """Calculate file checksum"""
        algorithm = algorithm.lower()
        
        if algorithm not in cls.ALGORITHMS:
            raise ValueError(f"Unsupported checksum algorithm: {algorithm}")
        
        if not file_path.exists():
            return None
        
        try:
            hash_obj = cls.ALGORITHMS[algorithm]()
            
            with open(file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(8192), b''):
                    hash_obj.update(chunk)
            
            return hash_obj.hexdigest()
            
        except Exception as e:
            logging.error(f"Error calculating checksum: {e}")
            return None


# =============================================================================
# MAIN DOWNLOAD MANAGER
# =============================================================================

class DownloadManager:
    """Main download manager class"""
    
    def __init__(self, config: Optional[DownloadConfig] = None):
        self.config = config or DownloadConfig()
        self.logger = logging.getLogger(__name__)
        
    def download_file(self, url: str, output_path: Path, 
                      expected_checksum: Optional[str] = None,
                      checksum_algorithm: str = 'sha256',
                      resume: bool = True) -> DownloadResult:
        """
        Download a file from URL to output path
        
        Args:
            url: URL to download from
            output_path: Path to save the file
            expected_checksum: Expected checksum for verification
            checksum_algorithm: Algorithm for checksum verification
            resume: Whether to resume interrupted downloads
            
        Returns:
            DownloadResult with success status and details
        """
        start_time = time.time()
        
        try:
            # Create output directory if it doesn't exist
            output_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Check if file already exists and is valid
            if output_path.exists() and expected_checksum:
                if ChecksumVerifier.verify_file(output_path, expected_checksum, checksum_algorithm):
                    self.logger.info(f"File already exists and checksum verified: {output_path}")
                    return DownloadResult(
                        success=True,
                        file_path=output_path,
                        file_size=output_path.stat().st_size,
                        download_time=0.0,
                        checksum_verified=True,
                        checksum_value=expected_checksum
                    )
            
            # Perform download with retries
            for attempt in range(self.config.max_retries + 1):
                try:
                    result = self._download_with_resume(url, output_path, resume and attempt > 0)
                    
                    # Verify checksum if provided
                    checksum_verified = True
                    if expected_checksum:
                        checksum_verified = ChecksumVerifier.verify_file(
                            output_path, expected_checksum, checksum_algorithm
                        )
                        
                        if not checksum_verified:
                            if output_path.exists():
                                output_path.unlink()  # Remove invalid file
                            raise DownloadError(f"Checksum verification failed for {output_path}")
                    
                    # Calculate actual checksum for record
                    actual_checksum = ChecksumVerifier.calculate_checksum(output_path, checksum_algorithm)
                    
                    download_time = time.time() - start_time
                    
                    return DownloadResult(
                        success=True,
                        file_path=output_path,
                        file_size=output_path.stat().st_size,
                        download_time=download_time,
                        checksum_verified=checksum_verified,
                        checksum_value=actual_checksum
                    )
                    
                except Exception as e:
                    if attempt < self.config.max_retries:
                        delay = self.config.retry_delay * (self.config.retry_backoff ** attempt)
                        self.logger.warning(f"Download attempt {attempt + 1} failed: {e}")
                        self.logger.info(f"Retrying in {delay:.1f} seconds...")
                        time.sleep(delay)
                    else:
                        raise
            
        except Exception as e:
            self.logger.error(f"Download failed: {e}")
            return DownloadResult(
                success=False,
                error_message=str(e),
                download_time=time.time() - start_time
            )
    
    def _download_with_resume(self, url: str, output_path: Path, resume: bool = False) -> bool:
        """Internal method to download with optional resume capability"""
        
        # Prepare request headers
        headers = {
            'User-Agent': self.config.user_agent
        }
        
        resume_pos = 0
        if resume and output_path.exists():
            resume_pos = output_path.stat().st_size
            headers['Range'] = f'bytes={resume_pos}-'
            self.logger.info(f"Resuming download from byte {resume_pos}")
        
        # Create request
        req = Request(url, headers=headers)
        
        try:
            with urlopen(req, timeout=self.config.timeout) as response:
                # Get content length
                content_length = response.headers.get('Content-Length')
                total_size = int(content_length) if content_length else 0
                
                if resume_pos > 0:
                    total_size += resume_pos
                
                self.logger.info(f"Downloading: {url}")
                self.logger.info(f"Output: {output_path}")
                if total_size > 0:
                    self.logger.info(f"Size: {total_size / (1024*1024):.1f} MB")
                
                # Initialize progress reporter
                progress = ProgressReporter(total_size, self.config.show_progress)
                if resume_pos > 0:
                    progress.update(resume_pos)  # Account for existing data
                
                # Open file for writing (append if resuming)
                mode = 'ab' if resume else 'wb'
                with open(output_path, mode) as f:
                    while True:
                        chunk = response.read(self.config.chunk_size)
                        if not chunk:
                            break
                        
                        f.write(chunk)
                        progress.update(len(chunk))
                
                progress.finish()
                self.logger.info(f"Download completed: {output_path}")
                return True
                
        except HTTPError as e:
            if e.code == 416 and resume:  # Range not satisfiable - file already complete
                self.logger.info("File already complete")
                return True
            raise DownloadError(f"HTTP Error {e.code}: {e.reason}")
        
        except URLError as e:
            raise DownloadError(f"URL Error: {e.reason}")
        
        except Exception as e:
            raise DownloadError(f"Download error: {e}")
    
    def batch_download(self, download_list: List[Tuple[str, Path]], 
                       parallel: bool = True) -> Dict[str, DownloadResult]:
        """
        Download multiple files, optionally in parallel
        
        Args:
            download_list: List of (url, output_path) tuples
            parallel: Whether to download in parallel
            
        Returns:
            Dictionary mapping URLs to DownloadResults
        """
        results = {}
        
        if parallel and len(download_list) > 1:
            # Parallel downloads using threading
            import concurrent.futures
            
            max_workers = min(self.config.max_parallel, len(download_list))
            
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                # Submit all download tasks
                future_to_url = {
                    executor.submit(self.download_file, url, path): url
                    for url, path in download_list
                }
                
                # Collect results as they complete
                for future in concurrent.futures.as_completed(future_to_url):
                    url = future_to_url[future]
                    try:
                        result = future.result()
                        results[url] = result
                    except Exception as e:
                        results[url] = DownloadResult(
                            success=False,
                            error_message=str(e)
                        )
        else:
            # Sequential downloads
            for url, path in download_list:
                result = self.download_file(url, path)
                results[url] = result
        
        return results
    
    def get_download_info(self, url: str) -> Dict[str, any]:
        """Get information about a download without downloading"""
        try:
            req = Request(url, headers={'User-Agent': self.config.user_agent})
            
            with urlopen(req, timeout=self.config.timeout) as response:
                headers = dict(response.headers)
                
                info = {
                    'url': url,
                    'status_code': response.getcode(),
                    'content_length': int(headers.get('Content-Length', 0)),
                    'content_type': headers.get('Content-Type', 'unknown'),
                    'last_modified': headers.get('Last-Modified'),
                    'headers': headers,
                    'supports_resume': 'bytes' in headers.get('Accept-Ranges', ''),
                }
                
                return info
                
        except Exception as e:
            return {
                'url': url,
                'error': str(e),
                'success': False
            }


# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

def setup_logging(verbose: bool = False):
    """Setup logging configuration"""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(levelname)s: %(message)s'
    )


def cmd_download(args):
    """Download single file command"""
    config = DownloadConfig(
        max_retries=args.retries,
        timeout=args.timeout,
        show_progress=not args.quiet,
        chunk_size=args.chunk_size
    )
    
    manager = DownloadManager(config)
    
    url = args.url
    output_path = Path(args.output)
    
    # Handle checksum verification
    expected_checksum = None
    checksum_algorithm = 'sha256'
    
    if args.verify_md5:
        expected_checksum = args.verify_md5
        checksum_algorithm = 'md5'
    elif args.verify_sha1:
        expected_checksum = args.verify_sha1
        checksum_algorithm = 'sha1'
    elif args.verify_sha256:
        expected_checksum = args.verify_sha256
        checksum_algorithm = 'sha256'
    elif args.verify_sha512:
        expected_checksum = args.verify_sha512
        checksum_algorithm = 'sha512'
    
    result = manager.download_file(
        url, 
        output_path, 
        expected_checksum=expected_checksum,
        checksum_algorithm=checksum_algorithm,
        resume=not args.no_resume
    )
    
    if result.success:
        print(f"✓ Download successful: {result.file_path}")
        print(f"  Size: {result.file_size / (1024*1024):.1f} MB")
        print(f"  Time: {result.download_time:.1f}s")
        if result.checksum_verified:
            print(f"  ✓ Checksum verified ({checksum_algorithm.upper()})")
        return 0
    else:
        print(f"✗ Download failed: {result.error_message}")
        return 1


def cmd_batch_download(args):
    """Batch download command"""
    urls_file = Path(args.urls_file)
    
    if not urls_file.exists():
        print(f"Error: URLs file not found: {urls_file}")
        return 1
    
    # Parse URLs file
    download_list = []
    try:
        with open(urls_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                
                parts = line.split('\t')
                if len(parts) >= 2:
                    url, output = parts[0], parts[1]
                    download_list.append((url, Path(output)))
                else:
                    print(f"Warning: Invalid line {line_num} in {urls_file}")
    
    except Exception as e:
        print(f"Error reading URLs file: {e}")
        return 1
    
    if not download_list:
        print("No valid URLs found in file")
        return 1
    
    config = DownloadConfig(
        max_retries=args.retries,
        timeout=args.timeout,
        show_progress=not args.quiet,
        max_parallel=args.parallel
    )
    
    manager = DownloadManager(config)
    
    print(f"Starting batch download of {len(download_list)} files...")
    results = manager.batch_download(download_list, parallel=args.parallel > 1)
    
    # Report results
    successful = sum(1 for r in results.values() if r.success)
    failed = len(results) - successful
    
    print(f"\nBatch download completed:")
    print(f"  ✓ Successful: {successful}")
    print(f"  ✗ Failed: {failed}")
    
    if failed > 0:
        print("\nFailed downloads:")
        for url, result in results.items():
            if not result.success:
                print(f"  {url}: {result.error_message}")
    
    return 0 if failed == 0 else 1


def cmd_verify(args):
    """Verify file checksum command"""
    file_path = Path(args.file)
    expected_checksum = args.checksum
    algorithm = args.algorithm
    
    if not file_path.exists():
        print(f"Error: File not found: {file_path}")
        return 1
    
    try:
        is_valid = ChecksumVerifier.verify_file(file_path, expected_checksum, algorithm)
        
        if is_valid:
            print(f"✓ Checksum verification successful ({algorithm.upper()})")
            return 0
        else:
            actual_checksum = ChecksumVerifier.calculate_checksum(file_path, algorithm)
            print(f"✗ Checksum verification failed ({algorithm.upper()})")
            print(f"  Expected: {expected_checksum}")
            print(f"  Actual:   {actual_checksum}")
            return 1
            
    except Exception as e:
        print(f"Error verifying checksum: {e}")
        return 1


def cmd_get_info(args):
    """Get download info command"""
    config = DownloadConfig()
    manager = DownloadManager(config)
    
    info = manager.get_download_info(args.url)
    
    if 'error' in info:
        print(f"Error getting info: {info['error']}")
        return 1
    
    print(f"Download Information for: {info['url']}")
    print(f"  Status: {info['status_code']}")
    print(f"  Size: {info['content_length'] / (1024*1024):.1f} MB")
    print(f"  Type: {info['content_type']}")
    print(f"  Resume Support: {'Yes' if info['supports_resume'] else 'No'}")
    
    if info['last_modified']:
        print(f"  Last Modified: {info['last_modified']}")
    
    return 0


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Robust Download Manager for Minecraft Server Setup"
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
    parser.add_argument("-q", "--quiet", action="store_true", help="Suppress progress output")
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Download command
    download_parser = subparsers.add_parser("download", help="Download single file")
    download_parser.add_argument("url", help="URL to download")
    download_parser.add_argument("output", help="Output file path")
    download_parser.add_argument("--retries", type=int, default=3, help="Number of retries")
    download_parser.add_argument("--timeout", type=int, default=30, help="Timeout in seconds")
    download_parser.add_argument("--chunk-size", type=int, default=8192, help="Download chunk size")
    download_parser.add_argument("--no-resume", action="store_true", help="Disable resume capability")
    download_parser.add_argument("--verify-md5", help="Verify MD5 checksum")
    download_parser.add_argument("--verify-sha1", help="Verify SHA1 checksum")
    download_parser.add_argument("--verify-sha256", help="Verify SHA256 checksum")
    download_parser.add_argument("--verify-sha512", help="Verify SHA512 checksum")
    
    # Batch download command
    batch_parser = subparsers.add_parser("batch-download", help="Download multiple files")
    batch_parser.add_argument("urls_file", help="File containing URLs and output paths (tab-separated)")
    batch_parser.add_argument("--retries", type=int, default=3, help="Number of retries")
    batch_parser.add_argument("--timeout", type=int, default=30, help="Timeout in seconds")
    batch_parser.add_argument("--parallel", type=int, default=4, help="Max parallel downloads")
    
    # Verify command
    verify_parser = subparsers.add_parser("verify", help="Verify file checksum")
    verify_parser.add_argument("file", help="File to verify")
    verify_parser.add_argument("checksum", help="Expected checksum")
    verify_parser.add_argument("--algorithm", choices=['md5', 'sha1', 'sha256', 'sha512'], 
                               default='sha256', help="Checksum algorithm")
    
    # Get info command
    info_parser = subparsers.add_parser("get-info", help="Get download information")
    info_parser.add_argument("url", help="URL to get information about")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    setup_logging(args.verbose)
    
    # Execute command
    if args.command == "download":
        return cmd_download(args)
    elif args.command == "batch-download":
        return cmd_batch_download(args)
    elif args.command == "verify":
        return cmd_verify(args)
    elif args.command == "get-info":
        return cmd_get_info(args)
    else:
        print(f"Unknown command: {args.command}")
        return 1


if __name__ == "__main__":
    sys.exit(main())