#!/usr/bin/env python3
"""
Robust Virtual Try-On Makeup Model - Fixed Architecture
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.models as models

class RobustMakeupGenerator(nn.Module):
    """Robust Generator for Virtual Try-On Makeup"""
    
    def __init__(self, input_channels=3, output_channels=3, image_size=256):
        super(RobustMakeupGenerator, self).__init__()
        self.image_size = image_size
        
        # Encoder
        self.encoder = nn.Sequential(
            # Input: 3 channels (RGB)
            nn.Conv2d(input_channels, 64, 4, 2, 1),  # 256x256 -> 128x128
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(64, 128, 4, 2, 1),  # 128x128 -> 64x64
            nn.BatchNorm2d(128),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(128, 256, 4, 2, 1),  # 64x64 -> 32x32
            nn.BatchNorm2d(256),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(256, 512, 4, 2, 1),  # 32x32 -> 16x16
            nn.BatchNorm2d(512),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(512, 1024, 4, 2, 1),  # 16x16 -> 8x8
            nn.BatchNorm2d(1024),
            nn.LeakyReLU(0.2, inplace=True),
        )
        
        # Decoder
        self.decoder = nn.Sequential(
            nn.ConvTranspose2d(1024, 512, 4, 2, 1),  # 8x8 -> 16x16
            nn.BatchNorm2d(512),
            nn.ReLU(inplace=True),
            
            nn.ConvTranspose2d(512, 256, 4, 2, 1),  # 16x16 -> 32x32
            nn.BatchNorm2d(256),
            nn.ReLU(inplace=True),
            
            nn.ConvTranspose2d(256, 128, 4, 2, 1),  # 32x32 -> 64x64
            nn.BatchNorm2d(128),
            nn.ReLU(inplace=True),
            
            nn.ConvTranspose2d(128, 64, 4, 2, 1),  # 64x64 -> 128x128
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            
            nn.ConvTranspose2d(64, output_channels, 4, 2, 1),  # 128x128 -> 256x256
            nn.Tanh()
        )
        
        # Makeup style encoder
        self.style_encoder = nn.Sequential(
            nn.Conv2d(3, 32, 3, 1, 1),
            nn.ReLU(inplace=True),
            nn.Conv2d(32, 64, 3, 1, 1),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool2d((8, 8))
        )
        
        # Style injection layers
        self.style_injection = nn.ModuleList([
            nn.Conv2d(1024 + 64, 1024, 1, 1, 0),
            nn.Conv2d(512 + 64, 512, 1, 1, 0),
            nn.Conv2d(256 + 64, 256, 1, 1, 0),
            nn.Conv2d(128 + 64, 128, 1, 1, 0),
            nn.Conv2d(64 + 64, 64, 1, 1, 0),
        ])
    
    def forward(self, face_image, makeup_style, face_mask):
        """
        Forward pass with proper tensor size handling
        Args:
            face_image: [B, 3, H, W] - Input face image
            makeup_style: [B, 3, H, W] - Makeup style reference
            face_mask: [B, 1, H, W] - Face mask
        """
        batch_size = face_image.size(0)
        
        # Ensure all inputs are the same size
        target_size = (self.image_size, self.image_size)
        face_image = F.interpolate(face_image, size=target_size, mode='bilinear', align_corners=False)
        makeup_style = F.interpolate(makeup_style, size=target_size, mode='bilinear', align_corners=False)
        face_mask = F.interpolate(face_mask, size=target_size, mode='bilinear', align_corners=False)
        
        # Encode face image
        face_features = self.encoder(face_image)
        
        # Encode makeup style
        style_features = self.style_encoder(makeup_style)
        style_features = F.interpolate(style_features, size=face_features.shape[2:], mode='bilinear', align_corners=False)
        
        # Inject style information at different scales
        combined_features = torch.cat([face_features, style_features], dim=1)
        combined_features = self.style_injection[0](combined_features)
        
        # Decode with style information
        output = self.decoder(combined_features)
        
        # Ensure output is same size as input
        output = F.interpolate(output, size=target_size, mode='bilinear', align_corners=False)
        
        # Apply mask for blending
        face_mask_resized = F.interpolate(face_mask, size=target_size, mode='bilinear', align_corners=False)
        face_image_resized = F.interpolate(face_image, size=target_size, mode='bilinear', align_corners=False)
        
        # Blend with original face using mask
        final_output = output * face_mask_resized + face_image_resized * (1 - face_mask_resized)
        
        return final_output

class RobustDiscriminator(nn.Module):
    """Robust Discriminator for Virtual Try-On Makeup"""
    
    def __init__(self, input_channels=3, image_size=256):
        super(RobustDiscriminator, self).__init__()
        self.image_size = image_size
        
        self.model = nn.Sequential(
            # Input: 3 channels (RGB)
            nn.Conv2d(input_channels, 64, 4, 2, 1),  # 256x256 -> 128x128
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(64, 128, 4, 2, 1),  # 128x128 -> 64x64
            nn.BatchNorm2d(128),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(128, 256, 4, 2, 1),  # 64x64 -> 32x32
            nn.BatchNorm2d(256),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(256, 512, 4, 2, 1),  # 32x32 -> 16x16
            nn.BatchNorm2d(512),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(512, 1, 4, 1, 0),  # 16x16 -> 1x1
            nn.Sigmoid()
        )
    
    def forward(self, x):
        # Ensure input is correct size
        x = F.interpolate(x, size=(self.image_size, self.image_size), mode='bilinear', align_corners=False)
        return self.model(x)

class RobustVGGFeatureExtractor(nn.Module):
    """Robust VGG Feature Extractor for Perceptual Loss"""
    
    def __init__(self):
        super(RobustVGGFeatureExtractor, self).__init__()
        vgg = models.vgg19(pretrained=True)
        self.features = vgg.features[:36]  # Up to conv5_4
        
        # Freeze parameters
        for param in self.parameters():
            param.requires_grad = False
    
    def forward(self, x):
        return self.features(x)

def create_robust_models(device, image_size=256):
    """Create robust models for virtual try-on"""
    generator = RobustMakeupGenerator(image_size=image_size).to(device)
    discriminator = RobustDiscriminator(image_size=image_size).to(device)
    vgg_extractor = RobustVGGFeatureExtractor().to(device)
    
    return generator, discriminator, vgg_extractor




