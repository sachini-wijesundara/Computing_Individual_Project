#!/bin/bash

# Virtual Try-On Makeup Training Script
# This script automates the complete training process

set -e  # Exit on any error

echo "🎨 Starting Virtual Try-On Makeup Training Process..."
echo "=================================================="

# Check if we're in the right directory
if [ ! -f "requirements.txt" ]; then
    echo "❌ Error: Please run this script from the training directory"
    exit 1
fi

# Step 1: Setup Environment
echo "📦 Step 1: Setting up environment..."
python3 setup.py

# Step 2: Download face landmark predictor if not exists
echo "👤 Step 2: Setting up face detection models..."
if [ ! -f "models/shape_predictor_68_face_landmarks.dat" ]; then
    echo "Downloading face landmark predictor..."
    mkdir -p models
    wget -O models/shape_predictor_68_face_landmarks.dat.bz2 \
        http://dlib.net/files/shape_predictor_68_face_landmarks.dat.bz2
    bunzip2 models/shape_predictor_68_face_landmarks.dat.bz2
    echo "✅ Face landmark predictor downloaded"
else
    echo "✅ Face landmark predictor already exists"
fi

# Step 3: Extract datasets
echo "📁 Step 3: Extracting datasets..."
python3 data_processing/extract_datasets.py --extract --structure

# Step 4: Preprocess data
echo "🔄 Step 4: Preprocessing data..."
python3 data_processing/preprocess.py --split

# Step 5: Check if we have enough data
echo "📊 Step 5: Checking dataset..."
TRAIN_IMAGES=$(find data/train/images -name "*.jpg" | wc -l)
VAL_IMAGES=$(find data/val/images -name "*.jpg" | wc -l)

echo "Training images: $TRAIN_IMAGES"
echo "Validation images: $VAL_IMAGES"

if [ $TRAIN_IMAGES -lt 100 ]; then
    echo "⚠️  Warning: Very few training images ($TRAIN_IMAGES). Consider adding more data."
fi

# Step 6: Start training
echo "🚀 Step 6: Starting model training..."
echo "This may take several hours. Training logs will be saved to logs/ directory."

# Create default config if it doesn't exist
if [ ! -f "config.json" ]; then
    echo "Creating default configuration..."
    cat > config.json << EOF
{
  "image_size": 512,
  "batch_size": 4,
  "num_epochs": 100,
  "learning_rate": 0.0002,
  "lr_decay_epoch": 50,
  "perceptual_weight": 0.1,
  "l1_weight": 10.0,
  "num_workers": 2,
  "log_interval": 50,
  "save_interval": 5,
  "use_wandb": false,
  "experiment_name": "virtual_tryon_makeup"
}
EOF
fi

# Start training
python3 train.py --config config.json

echo "🎉 Training completed!"
echo "Check the checkpoints/ directory for saved models"
echo "Check the logs/ directory for training logs"
echo "Check the outputs/ directory for generated samples"

# Step 7: Test inference
echo "🧪 Step 7: Testing inference..."
if [ -f "checkpoints/best_model.pth" ]; then
    echo "Testing inference with best model..."
    mkdir -p test_images
    
    # Create a simple test if no test images exist
    if [ ! -f "test_images/test_face.jpg" ]; then
        echo "⚠️  No test images found. Please add test images to test_images/ directory"
        echo "   Expected files: test_face.jpg, test_makeup_style.jpg"
    else
        python3 inference/inference.py \
            --model checkpoints/best_model.pth \
            --face test_images/test_face.jpg \
            --style test_images/test_makeup_style.jpg \
            --output test_result.jpg
        
        if [ -f "test_result.jpg" ]; then
            echo "✅ Inference test successful! Result saved as test_result.jpg"
        else
            echo "❌ Inference test failed"
        fi
    fi
else
    echo "⚠️  No best model found. Training may have failed."
fi

echo ""
echo "📋 Next Steps:"
echo "1. Check training logs in logs/ directory"
echo "2. View generated samples in outputs/ directory"
echo "3. Test your model with inference/inference.py"
echo "4. Start the Flask API server: cd flask_api && python app.py"
echo "5. Run your Flutter app to test the integration"
echo ""
echo "🎨 Happy virtual makeup application!"
