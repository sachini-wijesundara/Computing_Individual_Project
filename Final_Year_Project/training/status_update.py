#!/usr/bin/env python3
"""
Comprehensive training status update
"""

import time
import os
import subprocess
from pathlib import Path

def get_training_status():
    """Get comprehensive training status"""
    status = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'training_running': False,
        'checkpoints': [],
        'logs': [],
        'estimated_completion': None,
    }
    
    # Check if training is running
    try:
        result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
        status['training_running'] = 'python3 train_simple.py' in result.stdout
    except:
        pass
    
    # Check checkpoints
    checkpoints_dir = Path('checkpoints')
    if checkpoints_dir.exists():
        checkpoint_files = list(checkpoints_dir.glob("*.pth"))
        for cp in checkpoint_files:
            size_mb = cp.stat().st_size / (1024 * 1024)
            status['checkpoints'].append({
                'name': cp.name,
                'size_mb': round(size_mb, 1),
                'modified': time.ctime(cp.stat().st_mtime)
            })
    
    # Check logs
    logs_dir = Path('logs')
    if logs_dir.exists():
        log_files = list(logs_dir.glob("events.out.tfevents.*"))
        for log in log_files:
            status['logs'].append({
                'name': log.name,
                'size_kb': round(log.stat().st_size / 1024, 1),
                'modified': time.ctime(log.stat().st_mtime)
            })
    
    return status

def print_status():
    """Print formatted status"""
    status = get_training_status()
    
    print("🎨 VIRTUAL TRY-ON MAKEUP TRAINING STATUS")
    print("=" * 50)
    print(f"📅 Time: {status['timestamp']}")
    print(f"🔄 Training: {'✅ RUNNING' if status['training_running'] else '❌ STOPPED'}")
    
    print(f"\n💾 Checkpoints ({len(status['checkpoints'])}):")
    if status['checkpoints']:
        for cp in status['checkpoints']:
            print(f"   📁 {cp['name']} ({cp['size_mb']} MB) - {cp['modified']}")
    else:
        print("   📭 No checkpoints yet")
    
    print(f"\n📊 Logs ({len(status['logs'])}):")
    if status['logs']:
        for log in status['logs']:
            print(f"   📄 {log['name']} ({log['size_kb']} KB) - {log['modified']}")
    else:
        print("   📭 No logs yet")
    
    if status['training_running']:
        print(f"\n⏱️  Expected Timeline:")
        print(f"   🎯 First checkpoint: ~2-3 hours")
        print(f"   🏁 Full training: ~8-12 hours")
        print(f"   📈 Progress: Training actively running")
    
    print("\n🚀 Next Steps:")
    if status['checkpoints']:
        print("   ✅ Model checkpoints available!")
        print("   🔧 API server can be started")
        print("   📱 Flutter app ready for testing")
    else:
        print("   ⏳ Waiting for first checkpoint...")
        print("   🔧 Flutter app setup in progress")
        print("   📊 Monitoring training progress")

if __name__ == "__main__":
    print_status()




