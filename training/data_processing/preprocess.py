#!/usr/bin/env python3
"""
Data preprocessing script for Virtual Try-On Makeup training
"""

import cv2
import numpy as np
import os
import json
import shutil
from pathlib import Path
import dlib
import face_recognition
from PIL import Image
import argparse
from tqdm import tqdm
import albumentations as A
from albumentations.pytorch import ToTensorV2

class FaceProcessor:
    """Class for processing faces in images"""
    
    def __init__(self):
        # Initialize face detection models
        self.face_detector = dlib.get_frontal_face_detector()
        self.predictor = dlib.shape_predictor("models/shape_predictor_68_face_landmarks.dat")
        
    def detect_faces(self, image):
        """Detect faces in an image"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        faces = self.face_detector(gray)
        return faces
    
    def get_landmarks(self, image, face):
        """Get facial landmarks for a detected face"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        landmarks = self.predictor(gray, face)
        return landmarks
    
    def extract_face_region(self, image, face, padding=50):
        """Extract face region with padding"""
        x, y, w, h = face.left(), face.top(), face.width(), face.height()
        
        # Add padding
        x = max(0, x - padding)
        y = max(0, y - padding)
        w = min(image.shape[1] - x, w + 2 * padding)
        h = min(image.shape[0] - y, h + 2 * padding)
        
        return image[y:y+h, x:x+w], (x, y, w, h)
    
    def create_face_mask(self, image, landmarks):
        """Create segmentation mask for facial features"""
        mask = np.zeros(image.shape[:2], dtype=np.uint8)
        
        # Create masks for different facial regions
        # This is a simplified version - you may want to use more sophisticated segmentation
        
        # Face outline
        face_points = np.array([[landmarks.part(i).x, landmarks.part(i).y] 
                               for i in range(17, 27)])
        cv2.fillPoly(mask, [face_points], 255)
        
        return mask

class DataPreprocessor:
    """Main data preprocessing class"""
    
    def __init__(self, input_dir, output_dir):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.face_processor = FaceProcessor()
        
        # Create output directories
        self.output_dir.mkdir(parents=True, exist_ok=True)
        (self.output_dir / "faces").mkdir(exist_ok=True)
        (self.output_dir / "masks").mkdir(exist_ok=True)
        (self.output_dir / "landmarks").mkdir(exist_ok=True)
        
        # Define image transformations
        self.transform = A.Compose([
            A.Resize(512, 512),
            A.HorizontalFlip(p=0.5),
            A.RandomBrightnessContrast(p=0.3),
            A.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
            ToTensorV2()
        ])
    
    def process_image(self, image_path, output_name):
        """Process a single image"""
        try:
            # Load image
            image = cv2.imread(str(image_path))
            if image is None:
                return False
            
            # Detect faces
            faces = self.face_processor.detect_faces(image)
            if len(faces) == 0:
                return False
            
            # Use the largest face
            face = max(faces, key=lambda x: x.width() * x.height())
            
            # Extract face region
            face_region, bbox = self.face_processor.extract_face_region(image, face)
            
            # Get landmarks
            landmarks = self.face_processor.get_landmarks(image, face)
            
            # Create face mask
            mask = self.face_processor.create_face_mask(image, landmarks)
            
            # Save processed data
            cv2.imwrite(str(self.output_dir / "faces" / f"{output_name}.jpg"), face_region)
            cv2.imwrite(str(self.output_dir / "masks" / f"{output_name}_mask.jpg"), mask)
            
            # Save landmarks as JSON
            landmarks_data = {
                "face_bbox": [face.left(), face.top(), face.width(), face.height()],
                "face_region_bbox": bbox,
                "landmarks": [[landmarks.part(i).x, landmarks.part(i).y] for i in range(68)]
            }
            
            with open(self.output_dir / "landmarks" / f"{output_name}.json", 'w') as f:
                json.dump(landmarks_data, f)
            
            return True
            
        except Exception as e:
            print(f"Error processing {image_path}: {e}")
            return False
    
    def process_dataset(self, dataset_name):
        """Process an entire dataset"""
        dataset_path = self.input_dir / dataset_name
        
        if not dataset_path.exists():
            print(f"Dataset {dataset_name} not found at {dataset_path}")
            return
        
        print(f"Processing dataset: {dataset_name}")
        
        # Find all image files
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff'}
        image_files = []
        
        for ext in image_extensions:
            image_files.extend(dataset_path.rglob(f"*{ext}"))
            image_files.extend(dataset_path.rglob(f"*{ext.upper()}"))
        
        print(f"Found {len(image_files)} images")
        
        # Process images
        processed_count = 0
        for i, image_path in enumerate(tqdm(image_files)):
            output_name = f"{dataset_name}_{i:06d}"
            if self.process_image(image_path, output_name):
                processed_count += 1
        
        print(f"Successfully processed {processed_count} images from {dataset_name}")
    
    def split_dataset(self, train_ratio=0.7, val_ratio=0.2):
        """Split processed data into train/val/test sets"""
        faces_dir = self.output_dir / "faces"
        masks_dir = self.output_dir / "masks"
        landmarks_dir = self.output_dir / "landmarks"
        
        # Get all processed files
        face_files = list(faces_dir.glob("*.jpg"))
        
        # Shuffle and split
        np.random.shuffle(face_files)
        
        n_total = len(face_files)
        n_train = int(n_total * train_ratio)
        n_val = int(n_total * val_ratio)
        
        train_files = face_files[:n_train]
        val_files = face_files[n_train:n_train + n_val]
        test_files = face_files[n_train + n_val:]
        
        # Create splits
        for split, files in [("train", train_files), ("val", val_files), ("test", test_files)]:
            split_dir = Path(f"data/{split}")
            split_dir.mkdir(parents=True, exist_ok=True)
            
            (split_dir / "images").mkdir(exist_ok=True)
            (split_dir / "masks").mkdir(exist_ok=True)
            (split_dir / "labels").mkdir(exist_ok=True)
            
            for face_file in files:
                base_name = face_file.stem
                
                # Copy files
                shutil.copy2(face_file, split_dir / "images")
                shutil.copy2(masks_dir / f"{base_name}_mask.jpg", split_dir / "masks")
                shutil.copy2(landmarks_dir / f"{base_name}.json", split_dir / "labels")
        
        print(f"Dataset split completed:")
        print(f"  Train: {len(train_files)} images")
        print(f"  Validation: {len(val_files)} images")
        print(f"  Test: {len(test_files)} images")

def main():
    parser = argparse.ArgumentParser(description="Preprocess datasets for virtual try-on training")
    parser.add_argument("--input_dir", default="data/raw", help="Input directory containing raw datasets")
    parser.add_argument("--output_dir", default="data/processed", help="Output directory for processed data")
    parser.add_argument("--dataset", help="Specific dataset to process (optional)")
    parser.add_argument("--split", action="store_true", help="Split processed data into train/val/test")
    
    args = parser.parse_args()
    
    preprocessor = DataPreprocessor(args.input_dir, args.output_dir)
    
    if args.dataset:
        preprocessor.process_dataset(args.dataset)
    else:
        # Process all available datasets
        for dataset_dir in Path(args.input_dir).iterdir():
            if dataset_dir.is_dir():
                preprocessor.process_dataset(dataset_dir.name)
    
    if args.split:
        preprocessor.split_dataset()

if __name__ == "__main__":
    main()
