#!/usr/bin/env python3
"""
Data Preprocessing Pipeline for Virtual Makeup Try-On
Handles face detection, alignment, and segmentation mask generation
"""

import os
import cv2
import numpy as np
import dlib
import face_recognition
from PIL import Image
import albumentations as A
from albumentations.pytorch import ToTensorV2
import json
from tqdm import tqdm
import argparse

class FacePreprocessor:
    def __init__(self, output_size=(512, 512)):
        self.output_size = output_size
        self.face_detector = dlib.get_frontal_face_detector()
        
        # Download dlib shape predictor if not exists
        predictor_path = "shape_predictor_68_face_landmarks.dat"
        if not os.path.exists(predictor_path):
            print("Downloading dlib shape predictor...")
            import urllib.request
            urllib.request.urlretrieve(
                "http://dlib.net/files/shape_predictor_68_face_landmarks.dat",
                predictor_path
            )
        
        self.landmark_predictor = dlib.shape_predictor(predictor_path)
        
        # Data augmentation pipeline
        self.transform = A.Compose([
            A.HorizontalFlip(p=0.5),
            A.RandomBrightnessContrast(brightness_limit=0.2, contrast_limit=0.2, p=0.5),
            A.HueSaturationValue(hue_shift_limit=20, sat_shift_limit=30, val_shift_limit=20, p=0.5),
            A.GaussNoise(var_limit=(10.0, 50.0), p=0.3),
            A.Blur(blur_limit=3, p=0.3),
            A.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
            ToTensorV2()
        ])
    
    def detect_face_landmarks(self, image):
        """Detect face landmarks using dlib"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        faces = self.face_detector(gray)
        
        if len(faces) == 0:
            return None, None
        
        # Use the largest face
        face = max(faces, key=lambda rect: rect.width() * rect.height())
        landmarks = self.landmark_predictor(gray, face)
        
        # Convert to numpy array
        points = np.array([[p.x, p.y] for p in landmarks.parts()])
        
        return face, points
    
    def align_face(self, image, landmarks):
        """Align face using eye landmarks"""
        # Get eye centers
        left_eye = np.mean(landmarks[36:42], axis=0)
        right_eye = np.mean(landmarks[42:48], axis=0)
        
        # Calculate angle
        dy = right_eye[1] - left_eye[1]
        dx = right_eye[0] - left_eye[0]
        angle = np.degrees(np.arctan2(dy, dx))
        
        # Calculate center
        center = (left_eye + right_eye) / 2
        
        # Rotate image
        M = cv2.getRotationMatrix2D(tuple(center), angle, 1.0)
        aligned = cv2.warpAffine(image, M, (image.shape[1], image.shape[0]))
        
        # Rotate landmarks
        landmarks_homogeneous = np.column_stack([landmarks, np.ones(landmarks.shape[0])])
        aligned_landmarks = (M @ landmarks_homogeneous.T).T
        
        return aligned, aligned_landmarks
    
    def create_lip_mask(self, landmarks, image_shape):
        """Create lip segmentation mask"""
        # Lip landmark indices (68-point model)
        upper_lip = [48, 49, 50, 51, 52, 53, 54, 55, 65, 64, 63, 62, 61, 60, 67, 66]
        lower_lip = [48, 60, 67, 66, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66]
        
        mask = np.zeros(image_shape[:2], dtype=np.uint8)
        
        # Create lip contour
        lip_points = landmarks[upper_lip + lower_lip[::-1]]
        cv2.fillPoly(mask, [lip_points.astype(np.int32)], 255)
        
        return mask
    
    def create_face_mask(self, landmarks, image_shape):
        """Create face oval mask"""
        # Face contour indices (68-point model)
        face_contour = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
        
        mask = np.zeros(image_shape[:2], dtype=np.uint8)
        face_points = landmarks[face_contour]
        cv2.fillPoly(mask, [face_points.astype(np.int32)], 255)
        
        return mask
    
    def process_image(self, image_path, output_dir):
        """Process a single image"""
        try:
            # Load image
            image = cv2.imread(image_path)
            if image is None:
                return None
            
            # Detect face and landmarks
            face, landmarks = self.detect_face_landmarks(image)
            if face is None:
                return None
            
            # Align face
            aligned_image, aligned_landmarks = self.align_face(image, landmarks)
            
            # Create masks
            lip_mask = self.create_lip_mask(aligned_landmarks, aligned_image.shape)
            face_mask = self.create_face_mask(aligned_landmarks, aligned_image.shape)
            
            # Resize to target size
            aligned_image = cv2.resize(aligned_image, self.output_size)
            lip_mask = cv2.resize(lip_mask, self.output_size)
            face_mask = cv2.resize(face_mask, self.output_size)
            
            # Save processed data
            base_name = os.path.splitext(os.path.basename(image_path))[0]
            
            # Save image
            cv2.imwrite(os.path.join(output_dir, 'images', f'{base_name}.jpg'), aligned_image)
            
            # Save masks
            cv2.imwrite(os.path.join(output_dir, 'lip_masks', f'{base_name}.png'), lip_mask)
            cv2.imwrite(os.path.join(output_dir, 'face_masks', f'{base_name}.png'), face_mask)
            
            # Save landmarks
            np.save(os.path.join(output_dir, 'landmarks', f'{base_name}.npy'), aligned_landmarks)
            
            return {
                'image': f'{base_name}.jpg',
                'lip_mask': f'{base_name}.png',
                'face_mask': f'{base_name}.png',
                'landmarks': f'{base_name}.npy'
            }
            
        except Exception as e:
            print(f"Error processing {image_path}: {e}")
            return None
    
    def process_dataset(self, input_dir, output_dir, max_images=None):
        """Process entire dataset"""
        # Create output directories
        os.makedirs(os.path.join(output_dir, 'images'), exist_ok=True)
        os.makedirs(os.path.join(output_dir, 'lip_masks'), exist_ok=True)
        os.makedirs(os.path.join(output_dir, 'face_masks'), exist_ok=True)
        os.makedirs(os.path.join(output_dir, 'landmarks'), exist_ok=True)
        
        # Get all image files
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp'}
        image_files = []
        
        for root, dirs, files in os.walk(input_dir):
            for file in files:
                if os.path.splitext(file.lower())[1] in image_extensions:
                    image_files.append(os.path.join(root, file))
        
        if max_images:
            image_files = image_files[:max_images]
        
        print(f"Processing {len(image_files)} images...")
        
        processed_data = []
        for image_path in tqdm(image_files):
            result = self.process_image(image_path, output_dir)
            if result:
                processed_data.append(result)
        
        # Save metadata
        with open(os.path.join(output_dir, 'metadata.json'), 'w') as f:
            json.dump(processed_data, f, indent=2)
        
        print(f"Successfully processed {len(processed_data)} images")
        return processed_data

def main():
    parser = argparse.ArgumentParser(description='Preprocess face images for makeup try-on training')
    parser.add_argument('--input_dir', type=str, required=True, help='Input directory with images')
    parser.add_argument('--output_dir', type=str, required=True, help='Output directory for processed data')
    parser.add_argument('--max_images', type=int, default=None, help='Maximum number of images to process')
    parser.add_argument('--output_size', type=int, nargs=2, default=[512, 512], help='Output image size')
    
    args = parser.parse_args()
    
    preprocessor = FacePreprocessor(output_size=tuple(args.output_size))
    preprocessor.process_dataset(args.input_dir, args.output_dir, args.max_images)

if __name__ == '__main__':
    main()
