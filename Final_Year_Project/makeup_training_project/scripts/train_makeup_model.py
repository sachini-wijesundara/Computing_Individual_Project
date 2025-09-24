#!/usr/bin/env python3
"""
Training Script for Virtual Makeup Try-On Model
Implements GAN training with perceptual and adversarial losses
"""

import os
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
import torchvision.transforms as transforms
from torchvision.utils import save_image
import numpy as np
from PIL import Image
import json
import argparse
from tqdm import tqdm
import wandb
from datetime import datetime

from makeup_transfer_model import create_model, MakeupTransferModel, Discriminator

class MakeupDataset(Dataset):
    """Dataset for makeup transfer training"""
    def __init__(self, data_dir, transform=None, mode='train'):
        self.data_dir = data_dir
        self.transform = transform
        self.mode = mode
        
        # Load metadata
        with open(os.path.join(data_dir, 'metadata.json'), 'r') as f:
            self.metadata = json.load(f)
        
        # Filter for training/validation
        split_idx = int(0.8 * len(self.metadata))
        if mode == 'train':
            self.metadata = self.metadata[:split_idx]
        else:
            self.metadata = self.metadata[split_idx:]
    
    def __len__(self):
        return len(self.metadata)
    
    def __getitem__(self, idx):
        item = self.metadata[idx]
        
        # Load images
        image_path = os.path.join(self.data_dir, 'images', item['image'])
        lip_mask_path = os.path.join(self.data_dir, 'lip_masks', item['lip_mask'])
        face_mask_path = os.path.join(self.data_dir, 'face_masks', item['face_mask'])
        
        image = Image.open(image_path).convert('RGB')
        lip_mask = Image.open(lip_mask_path).convert('L')
        face_mask = Image.open(face_mask_path).convert('L')
        
        # Apply transforms
        if self.transform:
            image = self.transform(image)
            lip_mask = self.transform(lip_mask)
            face_mask = self.transform(face_mask)
        
        # Normalize masks to [0, 1]
        lip_mask = lip_mask / 255.0
        face_mask = face_mask / 255.0
        
        # For training, we need source and target pairs
        # In a real scenario, you'd have paired data
        # For now, we'll use the same image as both source and target
        source_face = image
        target_face = image  # In practice, this would be the same face with makeup
        
        return {
            'source_face': source_face,
            'target_face': target_face,
            'lip_mask': lip_mask.unsqueeze(0),
            'face_mask': face_mask.unsqueeze(0)
        }

class MakeupTrainer:
    """Trainer class for makeup transfer model"""
    def __init__(self, config):
        self.config = config
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
        # Create models
        self.generator, self.discriminator = create_model(config)
        self.generator.to(self.device)
        self.discriminator.to(self.device)
        
        # Loss functions
        self.mse_loss = nn.MSELoss()
        self.l1_loss = nn.L1Loss()
        self.bce_loss = nn.BCELoss()
        
        # Optimizers
        self.g_optimizer = optim.Adam(
            self.generator.parameters(),
            lr=config['learning_rate'],
            betas=(0.5, 0.999)
        )
        self.d_optimizer = optim.Adam(
            self.discriminator.parameters(),
            lr=config['learning_rate'],
            betas=(0.5, 0.999)
        )
        
        # Learning rate schedulers
        self.g_scheduler = optim.lr_scheduler.StepLR(
            self.g_optimizer, step_size=config['lr_decay_step'], gamma=0.5
        )
        self.d_scheduler = optim.lr_scheduler.StepLR(
            self.d_optimizer, step_size=config['lr_decay_step'], gamma=0.5
        )
        
        # Initialize weights
        self.init_weights()
        
        # Create output directories
        os.makedirs(config['output_dir'], exist_ok=True)
        os.makedirs(os.path.join(config['output_dir'], 'checkpoints'), exist_ok=True)
        os.makedirs(os.path.join(config['output_dir'], 'samples'), exist_ok=True)
    
    def init_weights(self):
        """Initialize model weights"""
        def init_func(m):
            if isinstance(m, nn.Conv2d) or isinstance(m, nn.ConvTranspose2d):
                nn.init.normal_(m.weight.data, 0.0, 0.02)
            elif isinstance(m, nn.BatchNorm2d) or isinstance(m, nn.InstanceNorm2d):
                nn.init.normal_(m.weight.data, 1.0, 0.02)
                nn.init.constant_(m.bias.data, 0.0)
        
        self.generator.apply(init_func)
        self.discriminator.apply(init_func)
    
    def perceptual_loss(self, pred, target):
        """Calculate perceptual loss using VGG features"""
        pred_features = self.generator.extract_vgg_features(pred)
        target_features = self.generator.extract_vgg_features(target)
        
        loss = 0
        for pred_feat, target_feat in zip(pred_features, target_features):
            loss += self.l1_loss(pred_feat, target_feat)
        
        return loss / len(pred_features)
    
    def adversarial_loss(self, pred, is_real):
        """Calculate adversarial loss"""
        if is_real:
            target = torch.ones_like(pred)
        else:
            target = torch.zeros_like(pred)
        
        return self.bce_loss(pred, target)
    
    def train_generator(self, batch):
        """Train generator for one step"""
        self.g_optimizer.zero_grad()
        
        source_face = batch['source_face'].to(self.device)
        target_face = batch['target_face'].to(self.device)
        lip_mask = batch['lip_mask'].to(self.device)
        face_mask = batch['face_mask'].to(self.device)
        
        # Generate makeup transfer
        makeup_result, makeup_only = self.generator(
            source_face, target_face, lip_mask, face_mask
        )
        
        # Generator losses
        # 1. Reconstruction loss
        recon_loss = self.l1_loss(makeup_result, target_face)
        
        # 2. Perceptual loss
        perc_loss = self.perceptual_loss(makeup_result, target_face)
        
        # 3. Adversarial loss
        fake_pred = self.discriminator(makeup_result)
        adv_loss = self.adversarial_loss(fake_pred, True)
        
        # 4. Lip-specific loss
        lip_loss = self.l1_loss(
            makeup_result * lip_mask,
            target_face * lip_mask
        )
        
        # Total generator loss
        g_loss = (
            self.config['lambda_recon'] * recon_loss +
            self.config['lambda_perc'] * perc_loss +
            self.config['lambda_adv'] * adv_loss +
            self.config['lambda_lip'] * lip_loss
        )
        
        g_loss.backward()
        self.g_optimizer.step()
        
        return {
            'g_loss': g_loss.item(),
            'recon_loss': recon_loss.item(),
            'perc_loss': perc_loss.item(),
            'adv_loss': adv_loss.item(),
            'lip_loss': lip_loss.item()
        }
    
    def train_discriminator(self, batch):
        """Train discriminator for one step"""
        self.d_optimizer.zero_grad()
        
        source_face = batch['source_face'].to(self.device)
        target_face = batch['target_face'].to(self.device)
        lip_mask = batch['lip_mask'].to(self.device)
        face_mask = batch['face_mask'].to(self.device)
        
        # Generate fake images
        with torch.no_grad():
            fake_images, _ = self.generator(
                source_face, target_face, lip_mask, face_mask
            )
        
        # Real images
        real_pred = self.discriminator(target_face)
        real_loss = self.adversarial_loss(real_pred, True)
        
        # Fake images
        fake_pred = self.discriminator(fake_images.detach())
        fake_loss = self.adversarial_loss(fake_pred, False)
        
        # Total discriminator loss
        d_loss = (real_loss + fake_loss) * 0.5
        
        d_loss.backward()
        self.d_optimizer.step()
        
        return {
            'd_loss': d_loss.item(),
            'real_loss': real_loss.item(),
            'fake_loss': fake_loss.item()
        }
    
    def train_epoch(self, dataloader, epoch):
        """Train for one epoch"""
        self.generator.train()
        self.discriminator.train()
        
        g_losses = []
        d_losses = []
        
        pbar = tqdm(dataloader, desc=f'Epoch {epoch}')
        for batch_idx, batch in enumerate(pbar):
            # Train discriminator
            d_metrics = self.train_discriminator(batch)
            d_losses.append(d_metrics)
            
            # Train generator (every other step)
            if batch_idx % 2 == 0:
                g_metrics = self.train_generator(batch)
                g_losses.append(g_metrics)
            
            # Update progress bar
            if g_losses:
                pbar.set_postfix({
                    'G_Loss': f"{g_metrics['g_loss']:.4f}",
                    'D_Loss': f"{d_metrics['d_loss']:.4f}"
                })
        
        return g_losses, d_losses
    
    def validate(self, dataloader, epoch):
        """Validate the model"""
        self.generator.eval()
        
        total_loss = 0
        with torch.no_grad():
            for batch in tqdm(dataloader, desc='Validation'):
                source_face = batch['source_face'].to(self.device)
                target_face = batch['target_face'].to(self.device)
                lip_mask = batch['lip_mask'].to(self.device)
                face_mask = batch['face_mask'].to(self.device)
                
                makeup_result, _ = self.generator(
                    source_face, target_face, lip_mask, face_mask
                )
                
                loss = self.l1_loss(makeup_result, target_face)
                total_loss += loss.item()
        
        return total_loss / len(dataloader)
    
    def save_samples(self, dataloader, epoch, num_samples=8):
        """Save sample images"""
        self.generator.eval()
        
        with torch.no_grad():
            batch = next(iter(dataloader))
            source_face = batch['source_face'][:num_samples].to(self.device)
            target_face = batch['target_face'][:num_samples].to(self.device)
            lip_mask = batch['lip_mask'][:num_samples].to(self.device)
            face_mask = batch['face_mask'][:num_samples].to(self.device)
            
            makeup_result, makeup_only = self.generator(
                source_face, target_face, lip_mask, face_mask
            )
            
            # Create comparison grid
            comparison = torch.cat([
                source_face,
                target_face,
                makeup_result,
                makeup_only
            ], dim=0)
            
            save_image(
                comparison,
                os.path.join(self.config['output_dir'], 'samples', f'epoch_{epoch}.png'),
                nrow=num_samples,
                normalize=True,
                value_range=(-1, 1)
            )
    
    def save_checkpoint(self, epoch, g_losses, d_losses):
        """Save model checkpoint"""
        checkpoint = {
            'epoch': epoch,
            'generator_state_dict': self.generator.state_dict(),
            'discriminator_state_dict': self.discriminator.state_dict(),
            'g_optimizer_state_dict': self.g_optimizer.state_dict(),
            'd_optimizer_state_dict': self.d_optimizer.state_dict(),
            'g_scheduler_state_dict': self.g_scheduler.state_dict(),
            'd_scheduler_state_dict': self.d_scheduler.state_dict(),
            'config': self.config
        }
        
        torch.save(
            checkpoint,
            os.path.join(self.config['output_dir'], 'checkpoints', f'checkpoint_epoch_{epoch}.pth')
        )
    
    def train(self):
        """Main training loop"""
        # Initialize wandb
        if self.config.get('use_wandb', False):
            wandb.init(
                project='makeup-transfer',
                config=self.config,
                name=f'makeup_transfer_{datetime.now().strftime("%Y%m%d_%H%M%S")}'
            )
        
        # Data transforms
        transform = transforms.Compose([
            transforms.Resize((512, 512)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
        ])
        
        # Create datasets
        train_dataset = MakeupDataset(
            self.config['data_dir'], transform, mode='train'
        )
        val_dataset = MakeupDataset(
            self.config['data_dir'], transform, mode='val'
        )
        
        # Create dataloaders
        train_loader = DataLoader(
            train_dataset,
            batch_size=self.config['batch_size'],
            shuffle=True,
            num_workers=self.config['num_workers']
        )
        val_loader = DataLoader(
            val_dataset,
            batch_size=self.config['batch_size'],
            shuffle=False,
            num_workers=self.config['num_workers']
        )
        
        print(f"Training samples: {len(train_dataset)}")
        print(f"Validation samples: {len(val_dataset)}")
        
        # Training loop
        for epoch in range(self.config['num_epochs']):
            # Train
            g_losses, d_losses = self.train_epoch(train_loader, epoch)
            
            # Validate
            val_loss = self.validate(val_loader, epoch)
            
            # Update learning rates
            self.g_scheduler.step()
            self.d_scheduler.step()
            
            # Log metrics
            avg_g_loss = np.mean([loss['g_loss'] for loss in g_losses])
            avg_d_loss = np.mean([loss['d_loss'] for loss in d_losses])
            
            print(f"Epoch {epoch}: G_Loss={avg_g_loss:.4f}, D_Loss={avg_d_loss:.4f}, Val_Loss={val_loss:.4f}")
            
            if self.config.get('use_wandb', False):
                wandb.log({
                    'epoch': epoch,
                    'g_loss': avg_g_loss,
                    'd_loss': avg_d_loss,
                    'val_loss': val_loss,
                    'lr_g': self.g_optimizer.param_groups[0]['lr'],
                    'lr_d': self.d_optimizer.param_groups[0]['lr']
                })
            
            # Save samples
            if epoch % self.config['sample_interval'] == 0:
                self.save_samples(val_loader, epoch)
            
            # Save checkpoint
            if epoch % self.config['checkpoint_interval'] == 0:
                self.save_checkpoint(epoch, g_losses, d_losses)
        
        # Save final model
        self.save_checkpoint(self.config['num_epochs'] - 1, g_losses, d_losses)
        print("Training completed!")

def main():
    parser = argparse.ArgumentParser(description='Train makeup transfer model')
    parser.add_argument('--data_dir', type=str, required=True, help='Path to processed data directory')
    parser.add_argument('--output_dir', type=str, required=True, help='Output directory for checkpoints and samples')
    parser.add_argument('--batch_size', type=int, default=4, help='Batch size')
    parser.add_argument('--num_epochs', type=int, default=100, help='Number of epochs')
    parser.add_argument('--learning_rate', type=float, default=2e-4, help='Learning rate')
    parser.add_argument('--use_wandb', action='store_true', help='Use Weights & Biases for logging')
    
    args = parser.parse_args()
    
    # Configuration
    config = {
        'data_dir': args.data_dir,
        'output_dir': args.output_dir,
        'batch_size': args.batch_size,
        'num_epochs': args.num_epochs,
        'learning_rate': args.learning_rate,
        'num_workers': 4,
        'input_channels': 3,
        'base_channels': 64,
        'lambda_recon': 10.0,
        'lambda_perc': 1.0,
        'lambda_adv': 0.1,
        'lambda_lip': 5.0,
        'lr_decay_step': 30,
        'sample_interval': 5,
        'checkpoint_interval': 10,
        'use_wandb': args.use_wandb
    }
    
    # Create trainer and start training
    trainer = MakeupTrainer(config)
    trainer.train()

if __name__ == '__main__':
    main()
