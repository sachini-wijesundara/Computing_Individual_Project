# Virtual Makeup Try-On Training Pipeline

A complete machine learning pipeline for training AI-powered virtual makeup try-on models using AR technology.

## 🎯 Overview

This project provides a comprehensive solution for training deep learning models that can transfer makeup from reference images to live video feeds in real-time AR applications. The pipeline includes data preprocessing, model training, and evaluation components.

## 📁 Project Structure

```
makeup_training_project/
├── data/                          # Raw datasets
│   ├── CelebAMask-HQ-master/     # High-quality celebrity faces with masks
│   ├── HairAnalysis-master/      # Hair analysis dataset
│   └── images/                   # Additional face images
├── models/                        # Trained model checkpoints
├── scripts/                       # Training and evaluation scripts
│   ├── data_preprocessing.py     # Face detection and alignment
│   ├── makeup_transfer_model.py  # Model architecture
│   ├── train_makeup_model.py     # Training script
│   └── evaluate_model.py         # Evaluation script
├── outputs/                       # Generated outputs
├── requirements.txt              # Python dependencies
└── run_training_pipeline.py      # Complete pipeline runner
```

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Install dependencies
pip install -r requirements.txt

# Download dlib shape predictor (if not already downloaded)
wget http://dlib.net/files/shape_predictor_68_face_landmarks.dat
```

### 2. Run Complete Pipeline

```bash
# Run the entire training pipeline
python run_training_pipeline.py \
    --input_data_dir ./data/images \
    --output_dir ./training_output \
    --max_images 1000 \
    --batch_size 4 \
    --num_epochs 50 \
    --use_wandb
```

### 3. Individual Steps

#### Data Preprocessing
```bash
python scripts/data_preprocessing.py \
    --input_dir ./data/images \
    --output_dir ./processed_data \
    --max_images 1000 \
    --output_size 512 512
```

#### Model Training
```bash
python scripts/train_makeup_model.py \
    --data_dir ./processed_data \
    --output_dir ./model_output \
    --batch_size 4 \
    --num_epochs 50 \
    --learning_rate 2e-4 \
    --use_wandb
```

#### Model Evaluation
```bash
python scripts/evaluate_model.py \
    --model_path ./model_output/checkpoints/checkpoint_epoch_49.pth \
    --data_dir ./processed_data \
    --output_dir ./evaluation \
    --num_samples 50
```

## 🏗️ Model Architecture

The makeup transfer model consists of:

- **MakeupEncoder**: Extracts features from source and makeup reference images
- **AttentionModule**: Self-attention mechanism for better feature fusion
- **MakeupDecoder**: Generates the final makeup transfer result
- **Discriminator**: Adversarial training for realistic results

### Key Features:
- Face alignment using 68-point facial landmarks
- Lip-specific segmentation and enhancement
- Perceptual loss using VGG features
- Adversarial training with discriminator
- Real-time inference optimization

## 📊 Training Process

### Data Preprocessing
1. **Face Detection**: Uses dlib for robust face detection
2. **Landmark Detection**: 68-point facial landmark extraction
3. **Face Alignment**: Automatic rotation and scaling
4. **Mask Generation**: Lip and face segmentation masks
5. **Data Augmentation**: Brightness, contrast, and noise augmentation

### Training Strategy
1. **Generator Training**: 
   - Reconstruction loss (L1)
   - Perceptual loss (VGG features)
   - Adversarial loss
   - Lip-specific loss

2. **Discriminator Training**:
   - Real vs fake classification
   - Gradient penalty for stability

3. **Loss Weights**:
   - Reconstruction: 10.0
   - Perceptual: 1.0
   - Adversarial: 0.1
   - Lip-specific: 5.0

## 📈 Evaluation Metrics

- **MSE (Mean Squared Error)**: Pixel-level reconstruction quality
- **MAE (Mean Absolute Error)**: Average pixel difference
- **SSIM (Structural Similarity)**: Structural similarity index
- **Lip-specific metrics**: Focused evaluation on lip region

## 🔧 Configuration

### Training Parameters
```python
config = {
    'batch_size': 4,
    'num_epochs': 50,
    'learning_rate': 2e-4,
    'input_channels': 3,
    'base_channels': 64,
    'lambda_recon': 10.0,
    'lambda_perc': 1.0,
    'lambda_adv': 0.1,
    'lambda_lip': 5.0,
    'lr_decay_step': 30,
    'sample_interval': 5,
    'checkpoint_interval': 10
}
```

## 🎨 Integration with Flutter AR App

After training, integrate the model with your Flutter app:

1. **Convert to ONNX**: Export PyTorch model to ONNX format
2. **Optimize for Mobile**: Use TensorRT or CoreML optimization
3. **Real-time Inference**: Implement efficient inference pipeline
4. **AR Integration**: Combine with MediaPipe face detection

### Example Integration:
```dart
// Load trained model
final model = await loadMakeupModel();

// Process frame
final result = await model.transferMakeup(
  sourceFace: currentFrame,
  makeupReference: selectedMakeup,
  lipMask: detectedLipMask,
  faceMask: detectedFaceMask
);
```

## 📱 Mobile Optimization

For real-time AR performance:

1. **Model Quantization**: Reduce model size with INT8 quantization
2. **TensorRT Optimization**: NVIDIA GPU acceleration
3. **CoreML Integration**: Apple Neural Engine utilization
4. **Memory Management**: Efficient tensor operations
5. **Frame Skipping**: Process every N-th frame for performance

## 🛠️ Troubleshooting

### Common Issues:

1. **CUDA Out of Memory**:
   - Reduce batch size
   - Use gradient accumulation
   - Enable mixed precision training

2. **Poor Quality Results**:
   - Increase training epochs
   - Adjust loss weights
   - Improve data quality

3. **Slow Training**:
   - Use multiple GPUs
   - Increase batch size
   - Enable mixed precision

### Performance Tips:

- Use SSD storage for faster data loading
- Enable pin_memory for DataLoader
- Use appropriate number of workers
- Monitor GPU utilization

## 📚 References

- [StyleGAN](https://github.com/NVlabs/stylegan) - Base architecture inspiration
- [MediaPipe](https://mediapipe.dev/) - Face detection and landmarks
- [CelebAMask-HQ](https://github.com/switchablenorms/CelebAMask-HQ) - Dataset
- [dlib](http://dlib.net/) - Face detection and landmarks

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For questions and support:
- Create an issue in the repository
- Check the troubleshooting section
- Review the evaluation metrics

---

**Happy Training! 🎨✨**

