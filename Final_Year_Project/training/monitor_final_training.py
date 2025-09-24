#!/usr/bin/env python3
"""
Final Training Monitoring - Ensures 100% completion
"""

import time
import os
import subprocess
from pathlib import Path
import json

def get_final_training_status():
    """Get comprehensive final training status"""
    status = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'training_running': False,
        'checkpoints': [],
        'logs': [],
        'progress': {
            'current_epoch': 0,
            'total_epochs': 50,
            'completion_percentage': 0
        },
        'estimated_completion': None,
    }
    
    # Check if training is running
    try:
        result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
        status['training_running'] = 'python3 train_final.py' in result.stdout
    except:
        pass
    
    # Check checkpoints
    checkpoints_dir = Path('checkpoints_final')
    if checkpoints_dir.exists():
        checkpoint_files = list(checkpoints_dir.glob("*.pth"))
        for cp in checkpoint_files:
            size_mb = cp.stat().st_size / (1024 * 1024)
            status['checkpoints'].append({
                'name': cp.name,
                'size_mb': round(size_mb, 1),
                'modified': time.ctime(cp.stat().st_mtime)
            })
        
        # Try to determine current epoch from checkpoint names
        epoch_checkpoints = [cp for cp in checkpoint_files if 'checkpoint_epoch_' in cp.name]
        if epoch_checkpoints:
            latest_epoch = max([int(cp.name.split('_')[-1].split('.')[0]) for cp in epoch_checkpoints])
            status['progress']['current_epoch'] = latest_epoch
            status['progress']['completion_percentage'] = (latest_epoch / status['progress']['total_epochs']) * 100
    
    # Check logs
    logs_dir = Path('logs_final')
    if logs_dir.exists():
        log_files = list(logs_dir.glob("events.out.tfevents.*"))
        for log in log_files:
            status['logs'].append({
                'name': log.name,
                'size_kb': round(log.stat().st_size / 1024, 1),
                'modified': time.ctime(log.stat().st_mtime)
            })
    
    return status

def print_final_status():
    """Print formatted final training status"""
    status = get_final_training_status()
    
    print("🎨 FINAL VIRTUAL TRY-ON MAKEUP TRAINING")
    print("=" * 60)
    print(f"📅 Time: {status['timestamp']}")
    print(f"🔄 Training: {'✅ RUNNING' if status['training_running'] else '❌ STOPPED'}")
    
    # Progress bar
    progress = status['progress']['completion_percentage']
    bar_length = 30
    filled_length = int(bar_length * progress / 100)
    bar = '█' * filled_length + '░' * (bar_length - filled_length)
    
    print(f"\n📊 Progress: [{bar}] {progress:.1f}%")
    print(f"   Epoch: {status['progress']['current_epoch']}/{status['progress']['total_epochs']}")
    
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
        print(f"\n⏱️  Training Status:")
        print(f"   🎯 Current Epoch: {status['progress']['current_epoch']}")
        print(f"   📈 Progress: {status['progress']['completion_percentage']:.1f}%")
        print(f"   🏁 Target: 50 epochs (100%)")
        
        if status['progress']['current_epoch'] > 0:
            remaining_epochs = status['progress']['total_epochs'] - status['progress']['current_epoch']
            print(f"   ⏳ Remaining: {remaining_epochs} epochs")
    
    print("\n🚀 Next Steps:")
    if status['progress']['completion_percentage'] >= 100:
        print("   🎉 TRAINING COMPLETED 100%!")
        print("   ✅ Model ready for deployment")
        print("   🔧 API server can be started")
        print("   📱 Flutter app ready for testing")
    elif status['checkpoints']:
        print("   ✅ Model checkpoints available!")
        print("   🔧 Training in progress...")
        print("   📊 Monitoring progress...")
    else:
        print("   ⏳ Training starting...")
        print("   🔧 Initializing models...")
        print("   📊 Preparing data...")

def monitor_continuously():
    """Monitor training continuously until 100% completion"""
    print("🔍 Starting continuous monitoring...")
    print("Press Ctrl+C to stop monitoring")
    
    try:
        while True:
            print_final_status()
            print("\n" + "="*60)
            
            # Check if training is complete
            status = get_final_training_status()
            if status['progress']['completion_percentage'] >= 100:
                print("\n🎉🎉🎉 TRAINING COMPLETED 100%! 🎉🎉🎉")
                print("Your virtual try-on makeup model is ready!")
                break
            
            time.sleep(30)  # Check every 30 seconds
            
    except KeyboardInterrupt:
        print("\n👋 Monitoring stopped by user")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "--continuous":
        monitor_continuously()
    else:
        print_final_status()




