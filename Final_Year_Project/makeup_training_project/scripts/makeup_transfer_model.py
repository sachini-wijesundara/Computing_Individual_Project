#!/usr/bin/env python3
"""
Makeup Transfer Model Architecture
Based on StyleGAN and attention mechanisms for realistic makeup transfer
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import torchvision.models as models
from torchvision import transforms
import numpy as np

class ResidualBlock(nn.Module):
    """Residual block with instance normalization"""
    def __init__(self, in_channels, out_channels, stride=1):
        super(ResidualBlock, self).__init__()
        self.conv1 = nn.Conv2d(in_channels, out_channels, 3, stride, 1, bias=False)
        self.in1 = nn.InstanceNorm2d(out_channels)
        self.conv2 = nn.Conv2d(out_channels, out_channels, 3, 1, 1, bias=False)
        self.in2 = nn.InstanceNorm2d(out_channels)
        
        self.shortcut = nn.Sequential()
        if stride != 1 or in_channels != out_channels:
            self.shortcut = nn.Sequential(
                nn.Conv2d(in_channels, out_channels, 1, stride, bias=False),
                nn.InstanceNorm2d(out_channels)
            )
    
    def forward(self, x):
        residual = x
        out = F.relu(self.in1(self.conv1(x)))
        out = self.in2(self.conv2(out))
        out += self.shortcut(residual)
        return F.relu(out)

class AttentionModule(nn.Module):
    """Self-attention module for makeup transfer"""
    def __init__(self, in_channels):
        super(AttentionModule, self).__init__()
        self.query_conv = nn.Conv2d(in_channels, in_channels // 8, 1)
        self.key_conv = nn.Conv2d(in_channels, in_channels // 8, 1)
        self.value_conv = nn.Conv2d(in_channels, in_channels, 1)
        self.gamma = nn.Parameter(torch.zeros(1))
        
    def forward(self, x):
        batch_size, C, H, W = x.size()
        
        # Generate query, key, value
        query = self.query_conv(x).view(batch_size, -1, H * W).permute(0, 2, 1)
        key = self.key_conv(x).view(batch_size, -1, H * W)
        value = self.value_conv(x).view(batch_size, -1, H * W)
        
        # Compute attention
        attention = torch.bmm(query, key)
        attention = F.softmax(attention, dim=-1)
        
        # Apply attention to value
        out = torch.bmm(value, attention.permute(0, 2, 1))
        out = out.view(batch_size, C, H, W)
        
        return self.gamma * out + x

class MakeupEncoder(nn.Module):
    """Encoder for makeup features extraction"""
    def __init__(self, input_channels=3, base_channels=64):
        super(MakeupEncoder, self).__init__()
        
        # Initial convolution
        self.initial = nn.Sequential(
            nn.Conv2d(input_channels, base_channels, 7, 1, 3),
            nn.InstanceNorm2d(base_channels),
            nn.ReLU(inplace=True)
        )
        
        # Downsampling blocks
        self.down1 = nn.Sequential(
            nn.Conv2d(base_channels, base_channels * 2, 3, 2, 1),
            nn.InstanceNorm2d(base_channels * 2),
            nn.ReLU(inplace=True)
        )
        
        self.down2 = nn.Sequential(
            nn.Conv2d(base_channels * 2, base_channels * 4, 3, 2, 1),
            nn.InstanceNorm2d(base_channels * 4),
            nn.ReLU(inplace=True)
        )
        
        self.down3 = nn.Sequential(
            nn.Conv2d(base_channels * 4, base_channels * 8, 3, 2, 1),
            nn.InstanceNorm2d(base_channels * 8),
            nn.ReLU(inplace=True)
        )
        
        # Residual blocks
        self.res_blocks = nn.Sequential(
            ResidualBlock(base_channels * 8, base_channels * 8),
            ResidualBlock(base_channels * 8, base_channels * 8),
            ResidualBlock(base_channels * 8, base_channels * 8),
            ResidualBlock(base_channels * 8, base_channels * 8),
            ResidualBlock(base_channels * 8, base_channels * 8),
            ResidualBlock(base_channels * 8, base_channels * 8)
        )
        
        # Attention module
        self.attention = AttentionModule(base_channels * 8)
        
    def forward(self, x):
        x = self.initial(x)
        x = self.down1(x)
        x = self.down2(x)
        x = self.down3(x)
        x = self.res_blocks(x)
        x = self.attention(x)
        return x

class MakeupDecoder(nn.Module):
    """Decoder for makeup application"""
    def __init__(self, base_channels=64):
        super(MakeupDecoder, self).__init__()
        
        # Upsampling blocks
        self.up1 = nn.Sequential(
            nn.ConvTranspose2d(base_channels * 8, base_channels * 4, 3, 2, 1, 1),
            nn.InstanceNorm2d(base_channels * 4),
            nn.ReLU(inplace=True)
        )
        
        self.up2 = nn.Sequential(
            nn.ConvTranspose2d(base_channels * 4, base_channels * 2, 3, 2, 1, 1),
            nn.InstanceNorm2d(base_channels * 2),
            nn.ReLU(inplace=True)
        )
        
        self.up3 = nn.Sequential(
            nn.ConvTranspose2d(base_channels * 2, base_channels, 3, 2, 1, 1),
            nn.InstanceNorm2d(base_channels),
            nn.ReLU(inplace=True)
        )
        
        # Final output
        self.final = nn.Sequential(
            nn.Conv2d(base_channels, 3, 7, 1, 3),
            nn.Tanh()
        )
        
    def forward(self, x):
        x = self.up1(x)
        x = self.up2(x)
        x = self.up3(x)
        x = self.final(x)
        return x

class MakeupTransferModel(nn.Module):
    """Complete makeup transfer model"""
    def __init__(self, input_channels=3, base_channels=64):
        super(MakeupTransferModel, self).__init__()
        
        self.encoder = MakeupEncoder(input_channels, base_channels)
        self.decoder = MakeupDecoder(base_channels)
        
        # VGG feature extractor for perceptual loss
        vgg = models.vgg19(pretrained=True).features
        self.vgg_layers = nn.ModuleList([
            vgg[:4],   # relu1_2
            vgg[:9],   # relu2_2
            vgg[:18],  # relu3_4
            vgg[:27],  # relu4_4
        ])
        
        # Freeze VGG parameters
        for param in self.vgg_layers.parameters():
            param.requires_grad = False
    
    def extract_vgg_features(self, x):
        """Extract VGG features for perceptual loss"""
        features = []
        for layer in self.vgg_layers:
            x = layer(x)
            features.append(x)
        return features
    
    def forward(self, source_face, makeup_face, lip_mask, face_mask):
        """
        Forward pass for makeup transfer
        Args:
            source_face: Source face image [B, 3, H, W]
            makeup_face: Makeup reference image [B, 3, H, W]
            lip_mask: Lip segmentation mask [B, 1, H, W]
            face_mask: Face segmentation mask [B, 1, H, W]
        """
        # Encode both faces
        source_features = self.encoder(source_face)
        makeup_features = self.encoder(makeup_face)
        
        # Combine features (you can experiment with different fusion strategies)
        combined_features = source_features + makeup_features
        
        # Decode to get makeup transfer result
        makeup_result = self.decoder(combined_features)
        
        # Apply masks for realistic blending
        face_mask_expanded = face_mask.expand_as(makeup_result)
        lip_mask_expanded = lip_mask.expand_as(makeup_result)
        
        # Blend makeup with source face
        final_result = source_face * (1 - face_mask_expanded) + makeup_result * face_mask_expanded
        
        return final_result, makeup_result

class Discriminator(nn.Module):
    """Discriminator for adversarial training"""
    def __init__(self, input_channels=3, base_channels=64):
        super(Discriminator, self).__init__()
        
        self.model = nn.Sequential(
            # Input: 3 x 512 x 512
            nn.Conv2d(input_channels, base_channels, 4, 2, 1),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(base_channels, base_channels * 2, 4, 2, 1),
            nn.InstanceNorm2d(base_channels * 2),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(base_channels * 2, base_channels * 4, 4, 2, 1),
            nn.InstanceNorm2d(base_channels * 4),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(base_channels * 4, base_channels * 8, 4, 2, 1),
            nn.InstanceNorm2d(base_channels * 8),
            nn.LeakyReLU(0.2, inplace=True),
            
            nn.Conv2d(base_channels * 8, 1, 4, 1, 0),
            nn.Sigmoid()
        )
    
    def forward(self, x):
        return self.model(x)

def create_model(config):
    """Create model based on configuration"""
    generator = MakeupTransferModel(
        input_channels=config.get('input_channels', 3),
        base_channels=config.get('base_channels', 64)
    )
    
    discriminator = Discriminator(
        input_channels=config.get('input_channels', 3),
        base_channels=config.get('base_channels', 64)
    )
    
    return generator, discriminator

if __name__ == '__main__':
    # Test model
    model = MakeupTransferModel()
    x = torch.randn(1, 3, 512, 512)
    y = torch.randn(1, 3, 512, 512)
    lip_mask = torch.randn(1, 1, 512, 512)
    face_mask = torch.randn(1, 1, 512, 512)
    
    output, makeup = model(x, y, lip_mask, face_mask)
    print(f"Output shape: {output.shape}")
    print(f"Makeup shape: {makeup.shape}")
