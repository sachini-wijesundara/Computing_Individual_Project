#!/usr/bin/env python3
"""
Dataset extraction and organization script for Virtual Try-On Makeup
"""

import os
import zipfile
import shutil
from pathlib import Path
import argparse

def extract_zip_file(zip_path, extract_to):
    """Extract a zip file to the specified directory"""
    print(f"Extracting {zip_path} to {extract_to}...")
    
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_to)
    
    print(f"Successfully extracted {zip_path}")

def organize_datasets():
    """Organize extracted datasets into proper structure"""
    
    # Define source paths (adjust these based on where you downloaded the files)
    downloads_dir = Path.home() / "Downloads"
    
    # Define target paths
    data_dir = Path("data/raw")
    data_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract datasets
    datasets = [
        {
            "name": "HairAnalysis",
            "zip_file": downloads_dir / "HairAnalysis-master.zip",
            "extract_to": data_dir / "hair_analysis"
        },
        {
            "name": "CelebAMask",
            "zip_file": downloads_dir / "CelebAMask-HQ-master.zip", 
            "extract_to": data_dir / "celebamask_hq"
        },
        {
            "name": "Images",
            "zip_file": downloads_dir / "images.zip",
            "extract_to": data_dir / "images"
        }
    ]
    
    for dataset in datasets:
        if dataset["zip_file"].exists():
            extract_zip_file(dataset["zip_file"], dataset["extract_to"])
        else:
            print(f"Warning: {dataset['zip_file']} not found. Please ensure the file exists.")
    
    print("Dataset extraction completed!")

def create_dataset_structure():
    """Create the expected dataset directory structure"""
    structure = {
        "data/raw": [
            "hair_analysis/",
            "celebamask_hq/", 
            "images/"
        ],
        "data/processed": [
            "faces/",
            "masks/",
            "landmarks/",
            "segmentation/"
        ],
        "data/train": [
            "images/",
            "masks/",
            "labels/"
        ],
        "data/val": [
            "images/",
            "masks/", 
            "labels/"
        ],
        "data/test": [
            "images/",
            "masks/",
            "labels/"
        ]
    }
    
    for base_dir, subdirs in structure.items():
        for subdir in subdirs:
            Path(base_dir) / subdir
            Path(base_dir, subdir).mkdir(parents=True, exist_ok=True)
    
    print("Dataset structure created!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract and organize datasets")
    parser.add_argument("--extract", action="store_true", help="Extract downloaded zip files")
    parser.add_argument("--structure", action="store_true", help="Create dataset directory structure")
    
    args = parser.parse_args()
    
    if args.structure:
        create_dataset_structure()
    
    if args.extract:
        organize_datasets()
    
    if not args.extract and not args.structure:
        print("Usage: python extract_datasets.py --extract --structure")
        print("This will extract your downloaded datasets and create the directory structure.")
