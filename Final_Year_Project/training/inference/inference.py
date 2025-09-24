#!/usr/bin/env python3
"""
Inference script for Virtual Try-On Makeup Model
"""

import torch
import torch.nn.functional as F
from PIL import Image
import cv2
import numpy as np
from pathlib import Path
import argparse
import json

from models.virtual_tryon_model import MakeupGenerator, VGGFeatureExtractor

class MakeupInference:
    """Inference class for virtual try-on makeup"""
    
    def __init__(self, model_path, device='cuda'):
        self.device = torch.device(device if torch.cuda.is_available() else 'cpu')
        
        # Load model
        self.generator = MakeupGenerator().to(self.device)
        checkpoint = torch.load(model_path, map_location=self.device)
        self.generator.load_state_dict(checkpoint['generator_state_dict'])
        self.generator.eval()
        
        print(f"Model loaded from {model_path}")
        print(f"Using device: {self.device}")
    
    def preprocess_image(self, image_path, size=512):
        """Preprocess input image"""
        # Load image
        image = cv2.imread(str(image_path))
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        
        # Resize
        image = cv2.resize(image, (size, size))
        
        # Normalize
        image = image.astype(np.float32) / 255.0
        image = (image - 0.5) / 0.5
        
        # Convert to tensor
        image = torch.from_numpy(image).permute(2, 0, 1).unsqueeze(0)
        
        return image.to(self.device)
    
    def create_face_mask(self, image_size=512):
        """Create a simple face mask"""
        # This is a simplified mask - in practice, you'd use face segmentation
        mask = np.ones((image_size, image_size), dtype=np.float32)
        
        # Create a rough face shape
        center_x, center_y = image_size // 2, image_size // 2
        axes_x, axes_y = image_size // 3, image_size // 4
        
        y, x = np.ogrid[:image_size, :image_size]
        mask = ((x - center_x) / axes_x) ** 2 + ((y - center_y) / axes_y) ** 2 <= 1
        
        mask = mask.astype(np.float32)
        mask = torch.from_numpy(mask).unsqueeze(0).unsqueeze(0)
        
        return mask.to(self.device)
    
    def apply_makeup(self, face_image, makeup_style, face_mask=None):
        """Apply makeup to face image"""
        if face_mask is None:
            face_mask = self.create_face_mask(face_image.shape[-1])
        
        with torch.no_grad():
            result = self.generator(face_image, makeup_style, face_mask)
        
        return result
    
    def postprocess_image(self, tensor_image):
        """Convert tensor back to PIL image"""
        # Denormalize
        image = tensor_image.squeeze(0).permute(1, 2, 0).cpu().numpy()
        image = (image + 1) / 2
        image = np.clip(image, 0, 1)
        image = (image * 255).astype(np.uint8)
        
        return Image.fromarray(image)
    
    def preprocess_image_from_array(self, image_array):
        """Preprocess image from numpy array"""
        # Convert to PIL Image
        image = Image.fromarray(image_array)
        
        # Resize
        image = image.resize((512, 512))
        
        # Normalize
        image_array = np.array(image).astype(np.float32) / 255.0
        image_array = (image_array - 0.5) / 0.5
        
        # Convert to tensor
        image_tensor = torch.from_numpy(image_array).permute(2, 0, 1).unsqueeze(0)
        
        return image_tensor.to(self.device)
    
    def process_image_pair(self, face_image_path, makeup_style_path, output_path):
        """Process a pair of images (face + makeup style)"""
        # Preprocess images
        face_image = self.preprocess_image(face_image_path)
        makeup_style = self.preprocess_image(makeup_style_path)
        
        # Create face mask
        face_mask = self.create_face_mask()
        
        # Apply makeup
        result = self.apply_makeup(face_image, makeup_style, face_mask)
        
        # Postprocess
        output_image = self.postprocess_image(result)
        
        # Save result
        output_image.save(output_path)
        
        return output_image

def main():
    parser = argparse.ArgumentParser(description="Virtual Try-On Makeup Inference")
    parser.add_argument('--model', type=str, required=True, help='Path to trained model')
    parser.add_argument('--face', type=str, required=True, help='Path to face image')
    parser.add_argument('--style', type=str, required=True, help='Path to makeup style image')
    parser.add_argument('--output', type=str, required=True, help='Output image path')
    parser.add_argument('--device', type=str, default='cuda', help='Device to use')
    
    args = parser.parse_args()
    
    # Create inference object
    inference = MakeupInference(args.model, args.device)
    
    # Process images
    result = inference.process_image_pair(
        args.face,
        args.style,
        args.output
    )
    
    print(f"Makeup applied successfully! Result saved to {args.output}")

if __name__ == "__main__":
    main()
