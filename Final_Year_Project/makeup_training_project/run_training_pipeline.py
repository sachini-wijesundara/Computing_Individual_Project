#!/usr/bin/env python3
"""
Complete Training Pipeline for Virtual Makeup Try-On
Automates the entire process from data preprocessing to model evaluation
"""

import os
import sys
import subprocess
import argparse
import json
from datetime import datetime

def run_command(command, description):
    """Run a command and handle errors"""
    print(f"\n{'='*60}")
    print(f"STEP: {description}")
    print(f"{'='*60}")
    print(f"Running: {command}")
    
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
        print("✅ Success!")
        if result.stdout:
            print("Output:", result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        if e.stdout:
            print("Output:", e.stdout)
        if e.stderr:
            print("Error:", e.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(description='Run complete makeup training pipeline')
    parser.add_argument('--input_data_dir', type=str, required=True, 
                       help='Path to directory containing raw images')
    parser.add_argument('--output_dir', type=str, default='./training_output',
                       help='Output directory for all results')
    parser.add_argument('--max_images', type=int, default=1000,
                       help='Maximum number of images to process')
    parser.add_argument('--batch_size', type=int, default=4,
                       help='Training batch size')
    parser.add_argument('--num_epochs', type=int, default=50,
                       help='Number of training epochs')
    parser.add_argument('--use_wandb', action='store_true',
                       help='Use Weights & Biases for logging')
    parser.add_argument('--skip_preprocessing', action='store_true',
                       help='Skip data preprocessing step')
    parser.add_argument('--skip_training', action='store_true',
                       help='Skip training step')
    parser.add_argument('--skip_evaluation', action='store_true',
                       help='Skip evaluation step')
    
    args = parser.parse_args()
    
    # Create output directory
    os.makedirs(args.output_dir, exist_ok=True)
    
    # Set up paths
    processed_data_dir = os.path.join(args.output_dir, 'processed_data')
    model_output_dir = os.path.join(args.output_dir, 'model_output')
    evaluation_output_dir = os.path.join(args.output_dir, 'evaluation')
    
    # Create subdirectories
    os.makedirs(processed_data_dir, exist_ok=True)
    os.makedirs(model_output_dir, exist_ok=True)
    os.makedirs(evaluation_output_dir, exist_ok=True)
    
    print("🎨 Virtual Makeup Try-On Training Pipeline")
    print("=" * 60)
    print(f"Input data: {args.input_data_dir}")
    print(f"Output directory: {args.output_dir}")
    print(f"Max images: {args.max_images}")
    print(f"Batch size: {args.batch_size}")
    print(f"Epochs: {args.num_epochs}")
    print(f"Use W&B: {args.use_wandb}")
    print("=" * 60)
    
    # Step 1: Data Preprocessing
    if not args.skip_preprocessing:
        print("\n🔧 STEP 1: Data Preprocessing")
        preprocess_cmd = f"""
        python scripts/data_preprocessing.py \
            --input_dir "{args.input_data_dir}" \
            --output_dir "{processed_data_dir}" \
            --max_images {args.max_images} \
            --output_size 512 512
        """
        
        if not run_command(preprocess_cmd, "Preprocessing face images and creating masks"):
            print("❌ Preprocessing failed. Exiting.")
            return False
    else:
        print("⏭️ Skipping preprocessing step")
    
    # Step 2: Model Training
    if not args.skip_training:
        print("\n🚀 STEP 2: Model Training")
        train_cmd = f"""
        python scripts/train_makeup_model.py \
            --data_dir "{processed_data_dir}" \
            --output_dir "{model_output_dir}" \
            --batch_size {args.batch_size} \
            --num_epochs {args.num_epochs} \
            --learning_rate 2e-4
        """
        
        if args.use_wandb:
            train_cmd += " --use_wandb"
        
        if not run_command(train_cmd, "Training makeup transfer model"):
            print("❌ Training failed. Exiting.")
            return False
    else:
        print("⏭️ Skipping training step")
    
    # Step 3: Model Evaluation
    if not args.skip_evaluation:
        print("\n📊 STEP 3: Model Evaluation")
        
        # Find the latest checkpoint
        checkpoint_dir = os.path.join(model_output_dir, 'checkpoints')
        if os.path.exists(checkpoint_dir):
            checkpoints = [f for f in os.listdir(checkpoint_dir) if f.endswith('.pth')]
            if checkpoints:
                latest_checkpoint = max(checkpoints, key=lambda x: int(x.split('_')[-1].split('.')[0]))
                checkpoint_path = os.path.join(checkpoint_dir, latest_checkpoint)
                
                eval_cmd = f"""
                python scripts/evaluate_model.py \
                    --model_path "{checkpoint_path}" \
                    --data_dir "{processed_data_dir}" \
                    --output_dir "{evaluation_output_dir}" \
                    --num_samples 50 \
                    --batch_size {args.batch_size}
                """
                
                if not run_command(eval_cmd, "Evaluating trained model"):
                    print("❌ Evaluation failed.")
                    return False
            else:
                print("⚠️ No checkpoints found for evaluation")
        else:
            print("⚠️ No checkpoint directory found for evaluation")
    else:
        print("⏭️ Skipping evaluation step")
    
    # Step 4: Generate Summary Report
    print("\n📋 STEP 4: Generating Summary Report")
    
    summary = {
        "pipeline_completed": True,
        "timestamp": datetime.now().isoformat(),
        "input_data_dir": args.input_data_dir,
        "output_dir": args.output_dir,
        "max_images": args.max_images,
        "batch_size": args.batch_size,
        "num_epochs": args.num_epochs,
        "use_wandb": args.use_wandb,
        "steps_completed": {
            "preprocessing": not args.skip_preprocessing,
            "training": not args.skip_training,
            "evaluation": not args.skip_evaluation
        }
    }
    
    # Save summary
    summary_path = os.path.join(args.output_dir, 'pipeline_summary.json')
    with open(summary_path, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print("\n🎉 PIPELINE COMPLETED SUCCESSFULLY!")
    print("=" * 60)
    print(f"📁 All outputs saved to: {args.output_dir}")
    print(f"📊 Processed data: {processed_data_dir}")
    print(f"🤖 Model outputs: {model_output_dir}")
    print(f"📈 Evaluation results: {evaluation_output_dir}")
    print(f"📋 Summary report: {summary_path}")
    print("=" * 60)
    
    # Print next steps
    print("\n🚀 NEXT STEPS:")
    print("1. Check the evaluation results in the evaluation directory")
    print("2. Review the generated sample images")
    print("3. If satisfied, integrate the trained model into your Flutter app")
    print("4. Use the model for real-time makeup transfer in AR")
    
    return True

if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)

