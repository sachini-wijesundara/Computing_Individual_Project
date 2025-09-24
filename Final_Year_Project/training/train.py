#!/usr/bin/env python3
"""
Training script for Virtual Try-On Makeup Model
"""

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader
from torch.utils.tensorboard import SummaryWriter
import argparse
import os
import json
from pathlib import Path
from tqdm import tqdm
import numpy as np
from PIL import Image
import wandb

from models.virtual_tryon_model import create_models, VirtualTryOnModel
from data_processing.dataset import VirtualTryOnDataset

class Trainer:
    """Main training class for Virtual Try-On Makeup"""
    
    def __init__(self, config):
        self.config = config
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
        # Create directories
        self.checkpoint_dir = Path('checkpoints')
        self.log_dir = Path('logs')
        self.output_dir = Path('outputs')
        
        for dir_path in [self.checkpoint_dir, self.log_dir, self.output_dir]:
            dir_path.mkdir(exist_ok=True)
        
        # Initialize models
        self.generator, self.discriminator, self.vgg_extractor = create_models(self.device)
        
        # Initialize optimizers
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
            self.g_optimizer, step_size=config['lr_decay_epoch'], gamma=0.5
        )
        self.d_scheduler = optim.lr_scheduler.StepLR(
            self.d_optimizer, step_size=config['lr_decay_epoch'], gamma=0.5
        )
        
        # Loss functions
        self.mse_loss = nn.MSELoss()
        self.l1_loss = nn.L1Loss()
        self.bce_loss = nn.BCELoss()
        
        # Tensorboard writer
        self.writer = SummaryWriter(self.log_dir)
        
        # Initialize wandb if enabled
        if config.get('use_wandb', False):
            wandb.init(
                project="virtual-tryon-makeup",
                config=config,
                name=f"run_{config.get('experiment_name', 'default')}"
            )
        
        # Training state
        self.current_epoch = 0
        self.global_step = 0
        
    def create_datasets(self):
        """Create training and validation datasets"""
        train_dataset = VirtualTryOnDataset(
            data_dir=Path('data/train'),
            image_size=self.config['image_size'],
            augment=True
        )
        
        val_dataset = VirtualTryOnDataset(
            data_dir=Path('data/val'),
            image_size=self.config['image_size'],
            augment=False
        )
        
        train_loader = DataLoader(
            train_dataset,
            batch_size=self.config['batch_size'],
            shuffle=True,
            num_workers=self.config['num_workers'],
            pin_memory=True
        )
        
        val_loader = DataLoader(
            val_dataset,
            batch_size=self.config['batch_size'],
            shuffle=False,
            num_workers=self.config['num_workers'],
            pin_memory=True
        )
        
        return train_loader, val_loader
    
    def generator_loss(self, fake_images, real_images, fake_pred, face_masks):
        """Calculate generator loss"""
        # Adversarial loss
        adversarial_loss = self.bce_loss(fake_pred, torch.ones_like(fake_pred))
        
        # Perceptual loss using VGG features
        real_features = self.vgg_extractor(real_images)
        fake_features = self.vgg_extractor(fake_images)
        
        perceptual_loss = 0
        for real_feat, fake_feat in zip(real_features, fake_features):
            perceptual_loss += self.l1_loss(fake_feat, real_feat)
        
        # L1 loss on masked regions
        face_masks_resized = torch.nn.functional.interpolate(
            face_masks, size=fake_images.shape[2:], mode='bilinear', align_corners=False
        )
        real_images_resized = torch.nn.functional.interpolate(
            real_images, size=fake_images.shape[2:], mode='bilinear', align_corners=False
        )
        masked_l1_loss = self.l1_loss(
            fake_images * face_masks_resized,
            real_images_resized * face_masks_resized
        )
        
        # Total generator loss
        total_loss = (
            adversarial_loss +
            self.config['perceptual_weight'] * perceptual_loss +
            self.config['l1_weight'] * masked_l1_loss
        )
        
        return total_loss, {
            'adversarial': adversarial_loss.item(),
            'perceptual': perceptual_loss.item(),
            'masked_l1': masked_l1_loss.item()
        }
    
    def discriminator_loss(self, real_pred, fake_pred):
        """Calculate discriminator loss"""
        real_loss = self.bce_loss(real_pred, torch.ones_like(real_pred))
        fake_loss = self.bce_loss(fake_pred, torch.zeros_like(fake_pred))
        
        total_loss = (real_loss + fake_loss) * 0.5
        return total_loss, {
            'real_loss': real_loss.item(),
            'fake_loss': fake_loss.item()
        }
    
    def train_epoch(self, train_loader):
        """Train for one epoch"""
        self.generator.train()
        self.discriminator.train()
        
        epoch_g_loss = 0
        epoch_d_loss = 0
        epoch_metrics = {
            'adversarial': 0, 'perceptual': 0, 'masked_l1': 0,
            'real_loss': 0, 'fake_loss': 0
        }
        
        pbar = tqdm(train_loader, desc=f'Epoch {self.current_epoch}')
        
        for batch_idx, batch in enumerate(pbar):
            # Move data to device
            face_images = batch['face_image'].to(self.device)
            makeup_styles = batch['makeup_style'].to(self.device)
            face_masks = batch['face_mask'].to(self.device)
            
            batch_size = face_images.size(0)
            
            # Train Discriminator
            self.d_optimizer.zero_grad()
            
            # Real images
            real_pred = self.discriminator(face_images)
            
            # Fake images
            with torch.no_grad():
                fake_images = self.generator(face_images, makeup_styles, face_masks)
            fake_pred = self.discriminator(fake_images.detach())
            
            d_loss, d_metrics = self.discriminator_loss(real_pred, fake_pred)
            d_loss.backward()
            self.d_optimizer.step()
            
            # Train Generator
            self.g_optimizer.zero_grad()
            
            fake_images = self.generator(face_images, makeup_styles, face_masks)
            fake_pred = self.discriminator(fake_images)
            
            g_loss, g_metrics = self.generator_loss(fake_images, face_images, fake_pred, face_masks)
            g_loss.backward()
            self.g_optimizer.step()
            
            # Update metrics
            epoch_g_loss += g_loss.item()
            epoch_d_loss += d_loss.item()
            
            for key in epoch_metrics:
                if key in g_metrics:
                    epoch_metrics[key] += g_metrics[key]
                if key in d_metrics:
                    epoch_metrics[key] += d_metrics[key]
            
            # Update progress bar
            pbar.set_postfix({
                'G_Loss': f'{g_loss.item():.4f}',
                'D_Loss': f'{d_loss.item():.4f}'
            })
            
            # Log to tensorboard
            if self.global_step % self.config['log_interval'] == 0:
                self.writer.add_scalar('Loss/Generator', g_loss.item(), self.global_step)
                self.writer.add_scalar('Loss/Discriminator', d_loss.item(), self.global_step)
                
                for key, value in g_metrics.items():
                    self.writer.add_scalar(f'Generator/{key}', value, self.global_step)
                
                for key, value in d_metrics.items():
                    self.writer.add_scalar(f'Discriminator/{key}', value, self.global_step)
            
            # Log to wandb
            if self.config.get('use_wandb', False) and self.global_step % self.config['log_interval'] == 0:
                wandb.log({
                    'Generator_Loss': g_loss.item(),
                    'Discriminator_Loss': d_loss.item(),
                    **{f'Generator/{k}': v for k, v in g_metrics.items()},
                    **{f'Discriminator/{k}': v for k, v in d_metrics.items()}
                }, step=self.global_step)
            
            self.global_step += 1
        
        # Average metrics
        num_batches = len(train_loader)
        epoch_g_loss /= num_batches
        epoch_d_loss /= num_batches
        
        for key in epoch_metrics:
            epoch_metrics[key] /= num_batches
        
        return epoch_g_loss, epoch_d_loss, epoch_metrics
    
    def validate(self, val_loader):
        """Validate the model"""
        self.generator.eval()
        
        total_loss = 0
        num_samples = 0
        
        with torch.no_grad():
            for batch in tqdm(val_loader, desc='Validation'):
                face_images = batch['face_image'].to(self.device)
                makeup_styles = batch['makeup_style'].to(self.device)
                face_masks = batch['face_mask'].to(self.device)
                
                fake_images = self.generator(face_images, makeup_styles, face_masks)
                fake_pred = self.discriminator(fake_images)
                
                loss, _ = self.generator_loss(fake_images, face_images, fake_pred, face_masks)
                total_loss += loss.item()
                num_samples += face_images.size(0)
        
        avg_loss = total_loss / len(val_loader)
        return avg_loss
    
    def save_checkpoint(self, epoch, is_best=False):
        """Save model checkpoint"""
        checkpoint = {
            'epoch': epoch,
            'generator_state_dict': self.generator.state_dict(),
            'discriminator_state_dict': self.discriminator.state_dict(),
            'g_optimizer_state_dict': self.g_optimizer.state_dict(),
            'd_optimizer_state_dict': self.d_optimizer.state_dict(),
            'config': self.config
        }
        
        # Save regular checkpoint
        checkpoint_path = self.checkpoint_dir / f'checkpoint_epoch_{epoch}.pth'
        torch.save(checkpoint, checkpoint_path)
        
        # Save best model
        if is_best:
            best_path = self.checkpoint_dir / 'best_model.pth'
            torch.save(checkpoint, best_path)
            print(f"New best model saved at epoch {epoch}")
    
    def load_checkpoint(self, checkpoint_path):
        """Load model checkpoint"""
        checkpoint = torch.load(checkpoint_path, map_location=self.device)
        
        self.generator.load_state_dict(checkpoint['generator_state_dict'])
        self.discriminator.load_state_dict(checkpoint['discriminator_state_dict'])
        self.g_optimizer.load_state_dict(checkpoint['g_optimizer_state_dict'])
        self.d_optimizer.load_state_dict(checkpoint['d_optimizer_state_dict'])
        
        self.current_epoch = checkpoint['epoch'] + 1
        print(f"Loaded checkpoint from epoch {checkpoint['epoch']}")
    
    def train(self):
        """Main training loop"""
        print("Starting training...")
        print(f"Device: {self.device}")
        print(f"Config: {self.config}")
        
        # Create datasets
        train_loader, val_loader = self.create_datasets()
        
        best_val_loss = float('inf')
        
        for epoch in range(self.current_epoch, self.config['num_epochs']):
            self.current_epoch = epoch
            
            # Train
            g_loss, d_loss, metrics = self.train_epoch(train_loader)
            
            # Validate
            val_loss = self.validate(val_loader)
            
            # Update learning rates
            self.g_scheduler.step()
            self.d_scheduler.step()
            
            # Print epoch results
            print(f"\nEpoch {epoch}/{self.config['num_epochs'] - 1}")
            print(f"Train G Loss: {g_loss:.4f}, D Loss: {d_loss:.4f}")
            print(f"Val Loss: {val_loss:.4f}")
            print(f"Metrics: {metrics}")
            
            # Save checkpoint
            is_best = val_loss < best_val_loss
            if is_best:
                best_val_loss = val_loss
            
            if epoch % self.config['save_interval'] == 0 or is_best:
                self.save_checkpoint(epoch, is_best)
            
            # Log epoch metrics
            self.writer.add_scalar('Epoch/Generator_Loss', g_loss, epoch)
            self.writer.add_scalar('Epoch/Discriminator_Loss', d_loss, epoch)
            self.writer.add_scalar('Epoch/Validation_Loss', val_loss, epoch)
        
        print("Training completed!")
        self.writer.close()

def main():
    parser = argparse.ArgumentParser(description="Train Virtual Try-On Makeup Model")
    parser.add_argument('--config', type=str, default='config.json', help='Path to config file')
    parser.add_argument('--resume', type=str, help='Path to checkpoint to resume from')
    parser.add_argument('--device', type=str, default='auto', help='Device to use (cuda/cpu/auto)')
    
    args = parser.parse_args()
    
    # Load config
    if os.path.exists(args.config):
        with open(args.config, 'r') as f:
            config = json.load(f)
    else:
        # Default config
        config = {
            'image_size': 512,
            'batch_size': 8,
            'num_epochs': 200,
            'learning_rate': 0.0002,
            'lr_decay_epoch': 100,
            'perceptual_weight': 0.1,
            'l1_weight': 10.0,
            'num_workers': 4,
            'log_interval': 100,
            'save_interval': 10,
            'use_wandb': False,
            'experiment_name': 'virtual_tryon_makeup'
        }
        
        # Save default config
        with open(args.config, 'w') as f:
            json.dump(config, f, indent=2)
    
    # Set device
    if args.device == 'auto':
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
    else:
        device = args.device
    
    # Create trainer
    trainer = Trainer(config)
    
    # Resume from checkpoint if specified
    if args.resume:
        trainer.load_checkpoint(args.resume)
    
    # Start training
    trainer.train()

if __name__ == "__main__":
    main()
