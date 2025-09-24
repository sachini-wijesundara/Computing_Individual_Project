# Virtual Try-On Makeup Model Training Guide

This guide will walk you through the complete process of training a virtual try-on makeup model using your downloaded datasets.

## 📋 Prerequisites

- Python 3.8+
- CUDA-compatible GPU (recommended)
- At least 16GB RAM
- 50GB+ free disk space

## 🚀 Quick Start

### 1. Setup Environment

```bash
cd /Users/sachiniwijesundara/development/apps/Final_Year_Project/training
python setup.py
```

### 2. Extract Your Datasets

```bash
# Extract and organize your downloaded datasets
python data_processing/extract_datasets.py --extract --structure
```

This will:
- Extract `HairAnalysis-master.zip` → `data/raw/hair_analysis/`
- Extract `CelebAMask-HQ-master.zip` → `data/raw/celebamask_hq/`
- Extract `images.zip` → `data/raw/images/`
- Create the proper directory structure

### 3. Preprocess Data

```bash
# Process all datasets for training
python data_processing/preprocess.py --split

# Or process specific dataset
python data_processing/preprocess.py --dataset celebamask_hq --split
```

This will:
- Detect faces in all images
- Extract facial landmarks
- Create face masks
- Split data into train/val/test sets

### 4. Start Training

```bash
# Train with default configuration
python train.py

# Train with custom config
python train.py --config custom_config.json

# Resume training from checkpoint
python train.py --resume checkpoints/checkpoint_epoch_50.pth
```

### 5. Test Inference

```bash
# Apply makeup to test images
python inference/inference.py --model checkpoints/best_model.pth \
    --face test_images/face.jpg \
    --style test_images/makeup_style.jpg \
    --output result.jpg
```

## 📁 Project Structure

```
training/
├── data/
│   ├── raw/                    # Extracted datasets
│   ├── processed/              # Preprocessed data
│   ├── train/                  # Training split
│   ├── val/                    # Validation split
│   └── test/                   # Test split
├── models/
│   └── virtual_tryon_model.py  # Model architecture
├── data_processing/
│   ├── extract_datasets.py     # Dataset extraction
│   ├── preprocess.py           # Data preprocessing
│   └── dataset.py              # Dataset classes
├── inference/
│   └── inference.py            # Inference script
├── flask_api/
│   └── app.py                  # Flask API server
├── checkpoints/                # Model checkpoints
├── logs/                       # Training logs
├── outputs/                    # Generated images
└── requirements.txt            # Dependencies
```

## 🎯 Model Architecture

The virtual try-on makeup model uses a **GAN-based approach** with:

### Generator
- **Input**: Face image (3 channels) + Makeup style (3 channels) + Face mask (1 channel)
- **Architecture**: U-Net with residual blocks
- **Features**: Attention mechanism for makeup regions
- **Output**: Makeup-applied face image

### Discriminator
- **Input**: Face image (3 channels)
- **Architecture**: PatchGAN discriminator
- **Purpose**: Distinguish real vs. generated makeup

### Loss Functions
1. **Adversarial Loss**: Generator vs. Discriminator
2. **Perceptual Loss**: VGG feature matching
3. **L1 Loss**: Pixel-level reconstruction on face regions

## ⚙️ Configuration

Create `config.json` for custom training:

```json
{
  "image_size": 512,
  "batch_size": 8,
  "num_epochs": 200,
  "learning_rate": 0.0002,
  "lr_decay_epoch": 100,
  "perceptual_weight": 0.1,
  "l1_weight": 10.0,
  "num_workers": 4,
  "log_interval": 100,
  "save_interval": 10,
  "use_wandb": false,
  "experiment_name": "virtual_tryon_makeup"
}
```

## 📊 Training Process

### Phase 1: Data Preparation (1-2 hours)
1. Extract datasets from zip files
2. Detect faces and extract landmarks
3. Create face masks and segmentation
4. Split into train/validation/test sets

### Phase 2: Model Training (12-24 hours)
1. **Epochs 1-50**: Basic adversarial training
2. **Epochs 51-100**: Add perceptual loss
3. **Epochs 101-150**: Fine-tune with face masks
4. **Epochs 151-200**: Final optimization

### Phase 3: Evaluation
1. Test on validation set
2. Generate sample results
3. Evaluate metrics (PSNR, SSIM, LPIPS)

## 🔧 Troubleshooting

### Common Issues

**1. CUDA Out of Memory**
```bash
# Reduce batch size in config.json
"batch_size": 4  # or 2
```

**2. Face Detection Fails**
```bash
# Download face landmark predictor
wget http://dlib.net/files/shape_predictor_68_face_landmarks.dat.bz2
bunzip2 shape_predictor_68_face_landmarks.dat.bz2
mv shape_predictor_68_face_landmarks.dat models/
```

**3. Poor Quality Results**
- Increase training epochs
- Adjust loss weights
- Use higher resolution images
- Add more data augmentation

### Performance Tips

1. **Use GPU**: Ensure CUDA is properly installed
2. **Batch Size**: Use largest batch size that fits in memory
3. **Data Loading**: Use multiple workers for data loading
4. **Mixed Precision**: Enable for faster training (optional)

## 📱 Flutter Integration

### 1. Start API Server

```bash
cd flask_api
pip install flask flask-cors
python app.py
```

### 2. Update Flutter App

The Flutter app is already configured with:
- `MakeupService` for API communication
- Camera integration for face capture
- Image picker for makeup styles
- Result display and saving

### 3. Test Integration

1. Run the Flutter app
2. Take a selfie or select a face image
3. Choose a makeup style
4. Apply virtual makeup
5. Save or share the result

## 📈 Expected Results

After training, you should see:
- **Realistic makeup application** on faces
- **Preserved facial features** and expressions
- **Smooth blending** between makeup and skin
- **Consistent results** across different face types

## 🎨 Customization

### Adding New Makeup Styles
1. Add style images to `data/makeup_styles/`
2. Update the style dataset
3. Retrain with new styles

### Improving Quality
1. **More Data**: Add more face images and makeup styles
2. **Better Preprocessing**: Improve face detection and alignment
3. **Advanced Models**: Try StyleGAN or other architectures
4. **Loss Functions**: Experiment with different loss combinations

## 📚 Additional Resources

- [PyTorch Documentation](https://pytorch.org/docs/)
- [GAN Training Tips](https://github.com/soumith/ganhacks)
- [Face Analysis Papers](https://paperswithcode.com/task/facial-landmark-detection)
- [Virtual Try-On Research](https://arxiv.org/search/cs?query=virtual+try-on)

## 🆘 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review the logs in `logs/` directory
3. Verify your dataset structure
4. Ensure all dependencies are installed correctly

Happy training! 🎉
