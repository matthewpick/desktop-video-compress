#!/usr/bin/env python3
"""
Desktop Video Compress - Automatic video compression for macOS
Watches ~/Desktop for .mov files and compresses them using HandBrake CLI
"""

import os
import sys
import time
import subprocess
import logging
import asyncio
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from desktop_notifier import DesktopNotifier

# Ensure log directory exists
log_dir = os.path.expanduser('~/Library/Logs')
os.makedirs(log_dir, exist_ok=True)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(log_dir, 'desktop-video-compress.log')),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Global variable to store HandBrakeCLI path once found
HANDBRAKE_PATH = None

# Global notifier instance for desktop notifications
NOTIFIER = DesktopNotifier(app_name="Desktop Video Compress")


def find_handbrake_cli():
    """Find HandBrakeCLI in common locations.
    
    Returns the full path to HandBrakeCLI if found, None otherwise.
    """
    # Common executable names (case variations)
    executable_names = ['HandBrakeCLI', 'handbrakecli']
    
    # Common installation paths (macOS Homebrew, Linux, etc.)
    search_paths = [
        '/opt/homebrew/bin',  # Apple Silicon Mac
        '/usr/local/bin',      # Intel Mac, Linux
        '/usr/bin',            # System-wide Linux
    ]
    
    # First, try to find it in PATH
    for exe_name in executable_names:
        try:
            result = subprocess.run(
                ['which', exe_name],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                path = result.stdout.strip()
                if os.path.isfile(path):
                    return path
        except Exception:
            pass
    
    # Then check common installation paths
    for search_path in search_paths:
        for exe_name in executable_names:
            full_path = os.path.join(search_path, exe_name)
            if os.path.isfile(full_path):
                return full_path
    
    return None


def check_handbrake_installed():
    """Check if HandBrake CLI is installed and available."""
    global HANDBRAKE_PATH
    
    HANDBRAKE_PATH = find_handbrake_cli()
    
    if HANDBRAKE_PATH is None:
        logger.error("HandBrake CLI not found in PATH or common locations")
        logger.error("Searched locations: /opt/homebrew/bin, /usr/local/bin, /usr/bin")
        send_notification(
            "Desktop Video Compress - Error",
            "HandBrake CLI is not installed. Please install it using: brew install handbrake"
        )
        return False
    
    try:
        result = subprocess.run(
            [HANDBRAKE_PATH, '--version'],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            version_info = result.stdout.split('\n')[0]
            logger.info(f"HandBrake CLI found at {HANDBRAKE_PATH}: {version_info}")
            return True
    except Exception as e:
        logger.error(f"Error checking HandBrake at {HANDBRAKE_PATH}: {e}")
        send_notification(
            "Desktop Video Compress - Error",
            f"Error checking HandBrake: {e}"
        )
        return False
    
    return False


def send_notification(title, message):
    """Send a desktop notification using desktop-notifier."""
    try:
        asyncio.run(NOTIFIER.send(title=title, message=message))
        logger.info(f"Notification sent: {title} - {message}")
    except Exception as e:
        logger.error(f"Failed to send notification: {e}")


def compress_video(input_path):
    """Compress video file using HandBrake CLI."""
    input_path = Path(input_path)
    
    # Skip if file doesn't exist or is already compressed
    if not input_path.exists():
        logger.warning(f"File not found: {input_path}")
        return
    
    # Create output filename with _compressed suffix
    output_path = input_path.parent / f"{input_path.stem}_compressed{input_path.suffix}"
    
    # Skip if already processed
    if output_path.exists():
        logger.info(f"Compressed file already exists: {output_path}")
        return
    
    # Skip if filename already contains _compressed
    if '_compressed' in input_path.stem:
        logger.info(f"Skipping already compressed file: {input_path}")
        return
    
    logger.info(f"Starting compression: {input_path}")
    send_notification(
        "Desktop Video Compress",
        f"Starting compression of {input_path.name}"
    )
    
    try:
        # HandBrake CLI command for web-optimized compression
        # Using fast preset with web optimization
        cmd = [
            HANDBRAKE_PATH,
            '-i', str(input_path),
            '-o', str(output_path),
            '--preset', 'Fast 1080p30',
            '--optimize',
            '--encoder', 'x264',
            '--quality', '22'
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=3600  # 1 hour timeout
        )
        
        if result.returncode == 0:
            # Get file sizes
            original_size = input_path.stat().st_size / (1024 * 1024)  # MB
            compressed_size = output_path.stat().st_size / (1024 * 1024)  # MB
            savings = ((original_size - compressed_size) / original_size) * 100
            
            message = f"Compressed {input_path.name}\nOriginal: {original_size:.1f}MB → Compressed: {compressed_size:.1f}MB ({savings:.1f}% savings)"
            logger.info(message)
            send_notification("Desktop Video Compress - Complete", message)
        else:
            error_msg = f"Compression failed: {result.stderr}"
            logger.error(error_msg)
            send_notification("Desktop Video Compress - Error", f"Failed to compress {input_path.name}")
            
    except subprocess.TimeoutExpired:
        logger.error(f"Compression timed out for {input_path}")
        send_notification("Desktop Video Compress - Error", f"Compression timed out for {input_path.name}")
    except Exception as e:
        logger.error(f"Error compressing video: {e}")
        send_notification("Desktop Video Compress - Error", f"Error: {str(e)}")


class DesktopVideoHandler(FileSystemEventHandler):
    """Handler for desktop video file events."""
    
    def __init__(self):
        super().__init__()
        self.processing = set()
    
    def on_created(self, event):
        """Handle file creation events."""
        if event.is_directory:
            return
        
        file_path = Path(event.src_path)
        
        # Only process .mov files
        if file_path.suffix.lower() != '.mov':
            return
        
        # Skip if already processing
        if str(file_path) in self.processing:
            return
        
        # Wait a bit to ensure file is fully written
        time.sleep(2)
        
        # Mark as processing
        self.processing.add(str(file_path))
        
        try:
            compress_video(file_path)
        finally:
            # Remove from processing set
            self.processing.discard(str(file_path))
    
    def on_modified(self, event):
        """Handle file modification events."""
        # Treat modifications as potential new files (for edge cases)
        if event.is_directory:
            return
        
        file_path = Path(event.src_path)
        
        # Only process .mov files
        if file_path.suffix.lower() != '.mov':
            return
        
        # Skip if already processing or already compressed
        if str(file_path) in self.processing or '_compressed' in file_path.stem:
            return


def main():
    """Main function to start the desktop video watcher."""
    logger.info("Starting Desktop Video Compress")
    
    # Check if HandBrake is installed
    if not check_handbrake_installed():
        logger.error("Exiting: HandBrake CLI is not available")
        sys.exit(1)
    
    # Get Desktop path
    desktop_path = os.path.expanduser('~/Desktop')
    
    if not os.path.exists(desktop_path):
        logger.error(f"Desktop path not found: {desktop_path}")
        sys.exit(1)
    
    logger.info(f"Watching for .mov files in: {desktop_path}")
    send_notification(
        "Desktop Video Compress",
        "Now watching Desktop for .mov files"
    )
    
    # Set up file watcher
    event_handler = DesktopVideoHandler()
    observer = Observer()
    observer.schedule(event_handler, desktop_path, recursive=False)
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logger.info("Stopping Desktop Video Compress")
        observer.stop()
        send_notification(
            "Desktop Video Compress",
            "Stopped watching Desktop"
        )
    
    observer.join()


if __name__ == '__main__':
    main()
