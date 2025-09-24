#!/usr/bin/env python3
"""
Evaluation Script for Virtual Makeup Try-On Model
Computes metrics and generates sample outputs
"""

import os
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import torchvision.transforms as transforms
from torchvision.utils import save_image
import numpy as np
from PIL import Image
import json
import argparse
from tqdm import tqdm
import cv2
from sklearn.metrics import mean_squared_error, mean_absolute_error
import matplotlib.pyplot as plt

from makeup_transfer_model import create_model
from train_makeup_model import MakeupDataset

class MakeupEvaluator:
    """Evaluator class for makeup transfer model"""
    def __init__(self, model_path, config, device='cuda'):
        self.device = torch.device(device if torch.cuda.is_available() else 'cpu')
        self.config = config
        
        # Load model
        self.generator, _ = create_model(config)
        checkpoint = torch.load(model_path, map_location=self.device)
        self.generator.load_state_dict(checkpoint['generator_state_dict'])
        self.generator.to(self.device)
        self.generator.eval()
        
        # Loss functions for evaluation
        self.mse_loss = nn.MSELoss()
        self.l1_loss = nn.L1Loss()
        self.ssim_loss = self._ssim_loss
    
    def _ssim_loss(self, pred, target):
        """Calculate SSIM loss"""
        def ssim(img1, img2, window_size=11, size_average=True):
            def gaussian(window_size, sigma=1.5):
                gauss = torch.Tensor([np.exp(-(x - window_size//2)**2/float(2*sigma**2)) for x in range(window_size)])
                return gauss/gauss.sum()
            
            def create_window(window_size, channel):
                _1D_window = gaussian(window_size).unsqueeze(1)
                _2D_window = _1D_window.mm(_1D_window.t()).float().unsqueeze(0).unsqueeze(0)
                window = _2D_window.expand(channel, 1, window_size, window_size).contiguous()
                return window
            
            channel = img1.size(1)
            window = create_window(window_size, channel).to(img1.device)
            
            mu1 = F.conv2d(img1, window, padding=window_size//2, groups=channel)
            mu2 = F.conv2d(img2, window, padding=window_size//2, groups=channel)
            
            mu1_sq = mu1.pow(2)
            mu2_sq = mu2.pow(2)
            mu1_mu2 = mu1*mu2
            
            sigma1_sq = F.conv2d(img1*img1, window, padding=window_size//2, groups=channel) - mu1_sq
            sigma2_sq = F.conv2d(img2*img2, window, padding=window_size//2, groups=channel) - mu2_sq
            sigma12 = F.conv2d(img1*img2, window, padding=window_size//2, groups=channel) - mu1_mu2
            
            C1 = 0.01**2
            C2 = 0.03**2
            
            ssim_map = ((2*mu1_mu2 + C1)*(2*sigma12 + C2))/((mu1_sq + mu2_sq + C1)*(sigma1_sq + sigma2_sq + C2))
            
            if size_average:
                return ssim_map.mean()
            else:
                return ssim_map.mean(1).mean(1).mean(1)
        
        return 1 - ssim(pred, target)
    
    def evaluate_dataset(self, dataloader):
        """Evaluate model on entire dataset"""
        mse_scores = []
        mae_scores = []
        ssim_scores = []
        lpips_scores = []
        
        with torch.no_grad():
            for batch in tqdm(dataloader, desc='Evaluating'):
                source_face = batch['source_face'].to(self.device)
                target_face = batch['target_face'].to(self.device)
                lip_mask = batch['lip_mask'].to(self.device)
                face_mask = batch['face_mask'].to(self.device)
                
                # Generate makeup transfer
                makeup_result, _ = self.generator(
                    source_face, target_face, lip_mask, face_mask
                )
                
                # Calculate metrics
                mse = self.mse_loss(makeup_result, target_face).item()
                mae = self.l1_loss(makeup_result, target_face).item()
                ssim = self.ssim_loss(makeup_result, target_face).item()
                
                mse_scores.append(mse)
                mae_scores.append(mae)
                ssim_scores.append(ssim)
        
        return {
            'mse': np.mean(mse_scores),
            'mae': np.mean(mae_scores),
            'ssim': np.mean(ssim_scores),
            'mse_std': np.std(mse_scores),
            'mae_std': np.std(mae_scores),
            'ssim_std': np.std(ssim_scores)
        }
    
    def generate_samples(self, dataloader, output_dir, num_samples=20):
        """Generate sample outputs"""
        os.makedirs(output_dir, exist_ok=True)
        
        sample_count = 0
        with torch.no_grad():
            for batch in dataloader:
                if sample_count >= num_samples:
                    break
                
                source_face = batch['source_face'].to(self.device)
                target_face = batch['target_face'].to(self.device)
                lip_mask = batch['lip_mask'].to(self.device)
                face_mask = batch['face_mask'].to(self.device)
                
                # Generate makeup transfer
                makeup_result, makeup_only = self.generator(
                    source_face, target_face, lip_mask, face_mask
                )
                
                # Save individual samples
                for i in range(source_face.size(0)):
                    if sample_count >= num_samples:
                        break
                    
                    # Denormalize images
                    source_img = self._denormalize(source_face[i])
                    target_img = self._denormalize(target_face[i])
                    result_img = self._denormalize(makeup_result[i])
                    makeup_img = self._denormalize(makeup_only[i])
                    
                    # Create comparison
                    comparison = torch.cat([
                        source_img, target_img, result_img, makeup_img
                    ], dim=2)  # Concatenate horizontally
                    
                    save_image(
                        comparison,
                        os.path.join(output_dir, f'sample_{sample_count:03d}.png'),
                        normalize=True,
                        value_range=(0, 1)
                    )
                    
                    sample_count += 1
    
    def _denormalize(self, tensor):
        """Denormalize tensor from [-1, 1] to [0, 1]"""
        return (tensor + 1) / 2
    
    def evaluate_lip_quality(self, dataloader):
        """Evaluate lip makeup quality specifically"""
        lip_mse_scores = []
        lip_mae_scores = []
        
        with torch.no_grad():
            for batch in tqdm(dataloader, desc='Evaluating lip quality'):
                source_face = batch['source_face'].to(self.device)
                target_face = batch['target_face'].to(self.device)
                lip_mask = batch['lip_mask'].to(self.device)
                face_mask = batch['face_mask'].to(self.device)
                
                # Generate makeup transfer
                makeup_result, _ = self.generator(
                    source_face, target_face, lip_mask, face_mask
                )
                
                # Focus on lip region
                lip_region_pred = makeup_result * lip_mask
                lip_region_target = target_face * lip_mask
                
                # Calculate lip-specific metrics
                lip_mse = self.mse_loss(lip_region_pred, lip_region_target).item()
                lip_mae = self.l1_loss(lip_region_pred, lip_region_target).item()
                
                lip_mse_scores.append(lip_mse)
                lip_mae_scores.append(lip_mae)
        
        return {
            'lip_mse': np.mean(lip_mse_scores),
            'lip_mae': np.mean(lip_mae_scores),
            'lip_mse_std': np.std(lip_mse_scores),
            'lip_mae_std': np.std(lip_mae_scores)
        }
    
    def create_evaluation_report(self, metrics, output_path):
        """Create detailed evaluation report"""
        report = f"""
# Makeup Transfer Model Evaluation Report

## Overall Performance Metrics
- **MSE (Mean Squared Error)**: {metrics['mse']:.6f} ± {metrics['mse_std']:.6f}
- **MAE (Mean Absolute Error)**: {metrics['mae']:.6f} ± {metrics['mae_std']:.6f}
- **SSIM (Structural Similarity)**: {metrics['ssim']:.6f} ± {metrics['ssim_std']:.6f}

## Lip-Specific Quality Metrics
- **Lip MSE**: {metrics['lip_mse']:.6f} ± {metrics['lip_mse_std']:.6f}
- **Lip MAE**: {metrics['lip_mae']:.6f} ± {metrics['lip_mae_std']:.6f}

## Interpretation
- **Lower MSE/MAE values** indicate better reconstruction quality
- **Higher SSIM values** (closer to 1.0) indicate better structural similarity
- **Lip-specific metrics** show how well the model performs on the most important region

## Recommendations
"""
        
        if metrics['ssim'] > 0.8:
            report += "- ✅ Good structural similarity achieved\n"
        else:
            report += "- ⚠️ Consider improving structural similarity\n"
        
        if metrics['lip_mae'] < 0.1:
            report += "- ✅ Excellent lip makeup quality\n"
        elif metrics['lip_mae'] < 0.2:
            report += "- ✅ Good lip makeup quality\n"
        else:
            report += "- ⚠️ Consider improving lip makeup quality\n"
        
        with open(output_path, 'w') as f:
            f.write(report)
        
        print(f"Evaluation report saved to {output_path}")

def main():
    parser = argparse.ArgumentParser(description='Evaluate makeup transfer model')
    parser.add_argument('--model_path', type=str, required=True, help='Path to trained model checkpoint')
    parser.add_argument('--data_dir', type=str, required=True, help='Path to processed data directory')
    parser.add_argument('--output_dir', type=str, required=True, help='Output directory for evaluation results')
    parser.add_argument('--num_samples', type=int, default=50, help='Number of samples to generate')
    parser.add_argument('--batch_size', type=int, default=4, help='Batch size for evaluation')
    
    args = parser.parse_args()
    
    # Load config from checkpoint
    checkpoint = torch.load(args.model_path, map_location='cpu')
    config = checkpoint['config']
    
    # Override config with command line args
    config['data_dir'] = args.data_dir
    config['batch_size'] = args.batch_size
    
    # Create evaluator
    evaluator = MakeupEvaluator(args.model_path, config)
    
    # Data transforms
    transform = transforms.Compose([
        transforms.Resize((512, 512)),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
    ])
    
    # Create dataset
    dataset = MakeupDataset(args.data_dir, transform, mode='val')
    dataloader = DataLoader(
        dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=4
    )
    
    print(f"Evaluating on {len(dataset)} samples...")
    
    # Evaluate overall performance
    print("Evaluating overall performance...")
    overall_metrics = evaluator.evaluate_dataset(dataloader)
    
    # Evaluate lip quality
    print("Evaluating lip quality...")
    lip_metrics = evaluator.evaluate_lip_quality(dataloader)
    
    # Combine metrics
    all_metrics = {**overall_metrics, **lip_metrics}
    
    # Generate samples
    print(f"Generating {args.num_samples} samples...")
    evaluator.generate_samples(dataloader, os.path.join(args.output_dir, 'samples'), args.num_samples)
    
    # Create evaluation report
    report_path = os.path.join(args.output_dir, 'evaluation_report.md')
    evaluator.create_evaluation_report(all_metrics, report_path)
    
    # Print summary
    print("\n" + "="*50)
    print("EVALUATION SUMMARY")
    print("="*50)
    print(f"MSE: {all_metrics['mse']:.6f} ± {all_metrics['mse_std']:.6f}")
    print(f"MAE: {all_metrics['mae']:.6f} ± {all_metrics['mae_std']:.6f}")
    print(f"SSIM: {all_metrics['ssim']:.6f} ± {all_metrics['ssim_std']:.6f}")
    print(f"Lip MSE: {all_metrics['lip_mse']:.6f} ± {all_metrics['lip_mse_std']:.6f}")
    print(f"Lip MAE: {all_metrics['lip_mae']:.6f} ± {all_metrics['lip_mae_std']:.6f}")
    print("="*50)

if __name__ == '__main__':
    main()
