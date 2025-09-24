#!/usr/bin/env python3
"""
Virtual Try-On Makeup Model Architecture
Based on GAN approach for realistic makeup application
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
from torchvision import models
import numpy as np

class ResidualBlock(nn.Module):
    """Residual block for the generator"""
    
    def __init__(self, in_channels, out_channels, stride=1):
        super(ResidualBlock, self).__init__()
        
        self.conv1 = nn.Conv2d(in_channels, out_channels, kernel_size=3, stride=stride, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_channels)
        self.conv2 = nn.Conv2d(out_channels, out_channels, kernel_size=3, stride=1, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_channels)
        
        self.shortcut = nn.Sequential()
        if stride != 1 or in_channels != out_channels:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_channels, out_channels, kernel_size=1, stride=stride, bias=False),
                nn.BatchNorm2d(out_channels)
            )
    
    def forward(self, x):
        residual = x
        out = F.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        out += self.shortcut(residual)
        out = F.relu(out)
        return out

class MakeupGenerator(nn.Module):
    """Generator network for virtual try-on makeup"""
    
    def __init__(self, input_channels=6, output_channels=3):
        super(MakeupGenerator, self).__init__()
        
        # Encoder
        self.encoder = nn.Sequential(
            # 512x512 -> 256x256
            nn.Conv2d(input_channels, 64, kernel_size=7, stride=1, padding=3, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            
            # 256x256 -> 128x128
            nn.Conv2d(64, 128, kernel_size=3, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            
            # 128x128 -> 64x64
            nn.Conv2d(128, 256, kernel_size=3, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
        )
        
        # Residual blocks
        self.res_blocks = nn.Sequential(
            ResidualBlock(256, 256),
            ResidualBlock(256, 256),
            ResidualBlock(256, 256),
            ResidualBlock(256, 256),
            ResidualBlock(256, 256),
            ResidualBlock(256, 256),
        )
        
        # Decoder
        self.decoder = nn.Sequential(
            # 64x64 -> 128x128
            nn.ConvTranspose2d(256, 128, kernel_size=3, stride=2, padding=1, output_padding=1, bias=False),
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            
            # 128x128 -> 256x256
            nn.ConvTranspose2d(128, 64, kernel_size=3, stride=2, padding=1, output_padding=1, bias=False),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            
            # 256x256 -> 512x512
            nn.ConvTranspose2d(64, 32, kernel_size=3, stride=2, padding=1, output_padding=1, bias=False),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            
            # Final output
            nn.Conv2d(32, output_channels, kernel_size=7, stride=1, padding=3),
            nn.Tanh()
        )
        
        # Attention mechanism for makeup regions
        self.attention = nn.Sequential(
            nn.Conv2d(256, 128, kernel_size=1),
            nn.ReLU(inplace=True),
            nn.Conv2d(128, 1, kernel_size=1),
            nn.Sigmoid()
        )
    
    def forward(self, face_image, makeup_style, face_mask):
        # Concatenate inputs: face_image (3) + makeup_style (3) = 6 channels
        x = torch.cat([face_image, makeup_style], dim=1)
        
        # Encode
        encoded = self.encoder(x)
        
        # Apply attention based on face mask
        attention_map = self.attention(encoded)
        encoded = encoded * attention_map
        
        # Residual blocks
        res_out = self.res_blocks(encoded)
        
        # Decode
        output = self.decoder(res_out)
        
        # Blend with original face using mask
        face_mask_resized = F.interpolate(face_mask, size=output.shape[2:], mode='bilinear', align_corners=False)
        face_image_resized = F.interpolate(face_image, size=output.shape[2:], mode='bilinear', align_corners=False)
        output = output * face_mask_resized + face_image_resized * (1 - face_mask_resized)
        
        return output

class MakeupDiscriminator(nn.Module):
    """Discriminator network for adversarial training"""
    
    def __init__(self, input_channels=3):
        super(MakeupDiscriminator, self).__init__()
        
        self.model = nn.Sequential(
            # 512x512 -> 256x256
            nn.Conv2d(input_channels, 64, kernel_size=4, stride=2, padding=1, bias=False),
            nn.LeakyReLU(0.2, inplace=True),
            
            # 256x256 -> 128x128
            nn.Conv2d(64, 128, kernel_size=4, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(128),
            nn.LeakyReLU(0.2, inplace=True),
            
            # 128x128 -> 64x64
            nn.Conv2d(128, 256, kernel_size=4, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(256),
            nn.LeakyReLU(0.2, inplace=True),
            
            # 64x64 -> 32x32
            nn.Conv2d(256, 512, kernel_size=4, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(512),
            nn.LeakyReLU(0.2, inplace=True),
            
            # 32x32 -> 16x16
            nn.Conv2d(512, 1024, kernel_size=4, stride=2, padding=1, bias=False),
            nn.BatchNorm2d(1024),
            nn.LeakyReLU(0.2, inplace=True),
            
            # Final classification
            nn.Conv2d(1024, 1, kernel_size=4, stride=1, padding=0),
            nn.Sigmoid()
        )
    
    def forward(self, x):
        return self.model(x)

class VGGFeatureExtractor(nn.Module):
    """VGG feature extractor for perceptual loss"""
    
    def __init__(self):
        super(VGGFeatureExtractor, self).__init__()
        vgg = models.vgg19(pretrained=True).features
        
        # Extract features from different layers
        self.layer1 = nn.Sequential(*list(vgg.children())[:2])   # conv1_1
        self.layer2 = nn.Sequential(*list(vgg.children())[2:7])  # conv2_2
        self.layer3 = nn.Sequential(*list(vgg.children())[7:12]) # conv3_4
        self.layer4 = nn.Sequential(*list(vgg.children())[12:21]) # conv4_4
        self.layer5 = nn.Sequential(*list(vgg.children())[21:30]) # conv5_4
        
        # Freeze parameters
        for param in self.parameters():
            param.requires_grad = False
    
    def forward(self, x):
        features = []
        x = self.layer1(x)
        features.append(x)
        x = self.layer2(x)
        features.append(x)
        x = self.layer3(x)
        features.append(x)
        x = self.layer4(x)
        features.append(x)
        x = self.layer5(x)
        features.append(x)
        return features

class VirtualTryOnModel(nn.Module):
    """Complete Virtual Try-On Makeup Model"""
    
    def __init__(self):
        super(VirtualTryOnModel, self).__init__()
        
        self.generator = MakeupGenerator()
        self.discriminator = MakeupDiscriminator()
        self.vgg_extractor = VGGFeatureExtractor()
        
        # Loss functions
        self.mse_loss = nn.MSELoss()
        self.l1_loss = nn.L1Loss()
        self.bce_loss = nn.BCELoss()
    
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
        face_masks_resized = F.interpolate(face_masks, size=fake_images.shape[2:], mode='bilinear', align_corners=False)
        masked_l1_loss = self.l1_loss(fake_images * face_masks_resized, real_images * face_masks_resized)
        
        # Total generator loss
        total_loss = adversarial_loss + 0.1 * perceptual_loss + 10.0 * masked_l1_loss
        
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

def create_models(device='cuda'):
    """Create and initialize models"""
    generator = MakeupGenerator().to(device)
    discriminator = MakeupDiscriminator().to(device)
    vgg_extractor = VGGFeatureExtractor().to(device)
    
    # Initialize weights
    def weights_init(m):
        if isinstance(m, (nn.Conv2d, nn.ConvTranspose2d)):
            nn.init.normal_(m.weight.data, 0.0, 0.02)
        elif isinstance(m, nn.BatchNorm2d):
            nn.init.normal_(m.weight.data, 1.0, 0.02)
            nn.init.constant_(m.bias.data, 0)
    
    generator.apply(weights_init)
    discriminator.apply(weights_init)
    
    return generator, discriminator, vgg_extractor

if __name__ == "__main__":
    # Test model creation
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    generator, discriminator, vgg_extractor = create_models(device)
    
    print(f"Generator parameters: {sum(p.numel() for p in generator.parameters()):,}")
    print(f"Discriminator parameters: {sum(p.numel() for p in discriminator.parameters()):,}")
    
    # Test forward pass
    batch_size = 2
    face_image = torch.randn(batch_size, 3, 512, 512).to(device)
    makeup_style = torch.randn(batch_size, 3, 512, 512).to(device)
    face_mask = torch.randn(batch_size, 1, 512, 512).to(device)
    
    fake_image = generator(face_image, makeup_style, face_mask)
    fake_pred = discriminator(fake_image)
    
    print(f"Generated image shape: {fake_image.shape}")
    print(f"Discriminator output shape: {fake_pred.shape}")
