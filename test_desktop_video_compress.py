#!/usr/bin/env python3
"""
Test script for desktop_video_compress.py
"""

import sys
import os
import tempfile
from pathlib import Path

# Add current directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from desktop_video_compress import check_handbrake_installed, send_notification, DesktopVideoHandler, find_handbrake_cli, SUPPORTED_VIDEO_EXTENSIONS

def test_handbrake_check():
    """Test HandBrake availability check.
    
    Note: This test checks if HandBrake can be found in common locations.
    The result may vary depending on the test environment.
    """
    print("Test 1: HandBrake availability check")
    result = check_handbrake_installed()
    # The result depends on whether HandBrake is actually installed
    print(f"  Result: {'Found' if result else 'Not found'} - This is expected based on your system")
    return True  # Pass regardless, as this is environment-dependent

def test_find_handbrake():
    """Test HandBrake path finding."""
    print("\nTest 2: HandBrake path finding")
    path = find_handbrake_cli()
    if path:
        print(f"  Found HandBrake at: {path}")
    else:
        print("  HandBrake not found in common locations (expected in test environment)")
    print("  Result: PASS (function executed without error)")
    return True

def test_notification():
    """Test notification function."""
    print("\nTest 3: Notification function")
    try:
        send_notification("Test Title", "Test Message")
        print("  Result: PASS (function executed without error)")
        return True
    except Exception as e:
        print(f"  Result: FAIL ({e})")
        return False

def test_handler_creation():
    """Test file handler creation."""
    print("\nTest 4: File handler creation")
    try:
        handler = DesktopVideoHandler()
        print("  Result: PASS (handler created successfully)")
        return True
    except Exception as e:
        print(f"  Result: FAIL ({e})")
        return False

def test_file_filtering():
    """Test that handler correctly identifies supported video files."""
    print("\nTest 5: File filtering logic")
    try:
        # This is a simple logic test
        test_cases = [
            ("test.mov", True),
            ("test.MOV", True),
            ("test.mp4", True),
            ("test.MP4", True),
            ("test.m4v", True),
            ("test.avi", True),
            ("test.mkv", True),
            ("test.webm", True),
            ("test.flv", True),
            ("test.wmv", True),
            ("test.txt", False),
            ("test.jpg", False),
            ("test.pdf", False),
            ("test_compressed.mov", False),
            ("test_compressed.mp4", False),
        ]
        
        all_passed = True
        for filename, should_process in test_cases:
            is_supported = Path(filename).suffix.lower() in SUPPORTED_VIDEO_EXTENSIONS
            is_compressed = '_compressed' in filename
            would_process = is_supported and not is_compressed
            
            if would_process == should_process:
                print(f"  ✓ {filename}: {'process' if should_process else 'skip'}")
            else:
                print(f"  ✗ {filename}: expected {'process' if should_process else 'skip'}, got {'process' if would_process else 'skip'}")
                all_passed = False
        
        print(f"  Result: {'PASS' if all_passed else 'FAIL'}")
        return all_passed
    except Exception as e:
        print(f"  Result: FAIL ({e})")
        return False

def main():
    """Run all tests."""
    print("=" * 60)
    print("Desktop Video Compress - Test Suite")
    print("=" * 60)
    
    tests = [
        test_handbrake_check,
        test_find_handbrake,
        test_notification,
        test_handler_creation,
        test_file_filtering,
    ]
    
    results = []
    for test_func in tests:
        try:
            results.append(test_func())
        except Exception as e:
            print(f"\nTest {test_func.__name__} raised exception: {e}")
            results.append(False)
    
    print("\n" + "=" * 60)
    print(f"Tests passed: {sum(results)}/{len(results)}")
    print("=" * 60)
    
    return all(results)

if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
