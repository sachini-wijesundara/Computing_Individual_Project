#!/usr/bin/env python3
"""
Dataset class for Virtual Try-On Makeup training
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

class VirtualTryOnDataset(Dataset):
    """Dataset for virtual try-on makeup training"""
    
    def __init__(self, data_dir, image_size=512, augment=True):
        self.data_dir = Path(data_dir)
        self.image_size = image_size
        self.augment = augment
        
        # Load data paths
        self.image_paths = list((self.data_dir / "images").glob("*.jpg"))
        self.mask_paths = list((self.data_dir / "masks").glob("*_mask.jpg"))
        self.label_paths = list((self.data_dir / "labels").glob("*.json"))
        
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
                A.HueSaturationValue(p=0.3),
                A.RandomGamma(p=0.3),
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
        
        # Create makeup style (for now, we'll use a simple approach)
        # In a real implementation, you might have separate makeup style images
        makeup_style = self._create_makeup_style(image, landmarks_data)
        
        return {
            'face_image': transformed['image'],
            'makeup_style': makeup_style,
            'face_mask': mask_transformed['image'],
            'landmarks': torch.tensor(landmarks_data['landmarks'], dtype=torch.float32),
            'image_path': str(pair['image'])
        }
    
    def _create_makeup_style(self, image, landmarks_data):
        """Create a makeup style image from the original image"""
        # This is a simplified approach - in practice, you'd have actual makeup style images
        
        # Convert to tensor and apply same transform as main image
        makeup_style = self.transform(image=image)['image']
        
        # Add some random variations to simulate different makeup styles
        noise = torch.randn_like(makeup_style) * 0.1
        makeup_style = makeup_style + noise
        makeup_style = torch.clamp(makeup_style, -1, 1)
        
        return makeup_style

class MakeupStyleDataset(Dataset):
    """Dataset for makeup style images"""
    
    def __init__(self, style_dir, image_size=512):
        self.style_dir = Path(style_dir)
        self.image_size = image_size
        
        # Load style images
        self.style_paths = []
        for ext in ['*.jpg', '*.jpeg', '*.png']:
            self.style_paths.extend(self.style_dir.glob(ext))
            self.style_paths.extend(self.style_dir.glob(ext.upper()))
        
        self.transform = A.Compose([
            A.Resize(image_size, image_size),
            A.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
            ToTensorV2()
        ])
        
        print(f"Found {len(self.style_paths)} makeup style images")
    
    def __len__(self):
        return len(self.style_paths)
    
    def __getitem__(self, idx):
        style_path = self.style_paths[idx]
        
        image = cv2.imread(str(style_path))
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        transformed = self.transform(image=image)
        
        return {
            'makeup_style': transformed['image'],
            'style_path': str(style_path)
        }

