#!/usr/bin/env python3
"""
Simplified dataset class for Virtual Try-On Makeup training
"""

import torch
from torch.utils.data import Dataset
import numpy as np
from PIL import Image
import cv2
import json
from pathlib import Path
import albumentations as A
from albumentations.pytorch import ToTensorV2

class SimpleVirtualTryOnDataset(Dataset):
    """Simplified dataset for virtual try-on makeup training"""
    
    def __init__(self, data_dir, image_size=256, augment=True):
        self.data_dir = Path(data_dir)
        self.image_size = image_size
        self.augment = augment
        
        # Load data paths
        self.image_paths = list((self.data_dir / "images").glob("*.jpg"))
        
        # Ensure we have matching files
        self.valid_pairs = []
        for img_path in self.image_paths:
            base_name = img_path.stem
            mask_path = self.data_dir / "masks" / f"{base_name}_mask.jpg"
            label_path = self.data_dir / "labels" / f"{base_name}.json"
            
            if mask_path.exists() and label_path.exists():
                self.valid_pairs.append({
                    'image': img_path,
                    'mask': mask_path,
                    'label': label_path
                })
        
        print(f"Found {len(self.valid_pairs)} valid image-mask-label pairs")
        
        # Define augmentations
        if augment:
            self.transform = A.Compose([
                A.Resize(image_size, image_size),
                A.HorizontalFlip(p=0.5),
                A.RandomBrightnessContrast(p=0.3),
                A.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
                ToTensorV2()
            ])
        else:
            self.transform = A.Compose([
                A.Resize(image_size, image_size),
                A.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
                ToTensorV2()
            ])
        
        # Mask transform (no augmentation for masks)
        self.mask_transform = A.Compose([
            A.Resize(image_size, image_size),
            A.Normalize(mean=[0.5], std=[0.5]),
            ToTensorV2()
        ])
    
    def __len__(self):
        return len(self.valid_pairs)
    
    def __getitem__(self, idx):
        pair = self.valid_pairs[idx]
        
        # Load image
        image = cv2.imread(str(pair['image']))
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        # Load mask
        mask = cv2.imread(str(pair['mask']), cv2.IMREAD_GRAYSCALE)
        
        # Load landmarks
        with open(pair['label'], 'r') as f:
            landmarks_data = json.load(f)
        
        # Apply transforms
        transformed = self.transform(image=image)
        mask_transformed = self.mask_transform(image=mask)
        
        # Create makeup style (simplified approach)
        makeup_style = self._create_simple_makeup_style(image)
        
        return {
            'face_image': transformed['image'],
            'makeup_style': makeup_style,
            'face_mask': mask_transformed['image'],
            'landmarks': torch.tensor(landmarks_data['landmarks'], dtype=torch.float32),
            'image_path': str(pair['image'])
        }
    
    def _create_simple_makeup_style(self, image):
        """Create a simple makeup style from the original image"""
        # Apply some basic transformations to simulate makeup
        makeup_image = image.copy()
        
        # Increase saturation slightly
        hsv = cv2.cvtColor(makeup_image, cv2.COLOR_RGB2HSV)
        hsv[:, :, 1] = hsv[:, :, 1] * 1.2  # Increase saturation
        hsv[:, :, 2] = hsv[:, :, 2] * 1.1  # Increase brightness slightly
        makeup_image = cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)
        
        # Apply the same transform as main image
        makeup_style = self.transform(image=makeup_image)['image']
        
        return makeup_style

