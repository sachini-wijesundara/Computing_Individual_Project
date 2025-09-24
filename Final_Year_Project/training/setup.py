#!/usr/bin/env python3
"""
Setup script for Virtual Try-On Makeup Model Training
"""

import os
import sys
import subprocess
import zipfile
from pathlib import Path

def create_directory_structure():
    """Create necessary directories for training"""
    directories = [
        'data/raw',
        'data/processed',
        'data/train',
        'data/val',
        'data/test',
        'models',
        'checkpoints',
        'logs',
        'outputs',
        'results'
    ]
    
    for directory in directories:
        Path(directory).mkdir(parents=True, exist_ok=True)
        print(f"Created directory: {directory}")

def install_dependencies():
    """Install required Python packages"""
    print("Installing dependencies...")
    try:
        subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-r', 'requirements.txt'])
        print("Dependencies installed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Error installing dependencies: {e}")
        print("Trying with python3...")
        subprocess.check_call(['python3', '-m', 'pip', 'install', '-r', 'requirements.txt'])
        print("Dependencies installed successfully!")

def setup_environment():
    """Set up the complete training environment"""
    print("Setting up Virtual Try-On Makeup Training Environment...")
    create_directory_structure()
    install_dependencies()
    print("Environment setup complete!")

if __name__ == "__main__":
    setup_environment()
