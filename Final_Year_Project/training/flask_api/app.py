#!/usr/bin/env python3
"""
Flask API for Virtual Try-On Makeup Model
Serves the trained model for inference via HTTP requests
"""

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import torch
import cv2
import numpy as np
from PIL import Image
import io
import base64
import os
from pathlib import Path

from inference.inference import MakeupInference

app = Flask(__name__)
CORS(app)

# Global variables
inference_engine = None
device = 'cuda' if torch.cuda.is_available() else 'cpu'

def initialize_model():
    """Initialize the trained model"""
    global inference_engine
    
    model_path = 'checkpoints/best_model.pth'
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model not found at {model_path}")
    
    inference_engine = MakeupInference(model_path, device)
    print(f"Model initialized on device: {device}")

@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'device': device,
        'model_loaded': inference_engine is not None
    })

@app.route('/api/apply_makeup', methods=['POST'])
def apply_makeup():
    """Apply virtual makeup to uploaded face image"""
    try:
        if inference_engine is None:
            return jsonify({'error': 'Model not loaded'}), 500
        
        # Check if files are present
        if 'face_image' not in request.files:
            return jsonify({'error': 'No face image provided'}), 400
        
        if 'makeup_style' not in request.files:
            return jsonify({'error': 'No makeup style provided'}), 400
        
        # Get uploaded files
        face_file = request.files['face_image']
        style_file = request.files['makeup_style']
        
        # Get makeup type
        makeup_type = request.form.get('makeup_type', 'general')
        
        # Read images
        face_image = Image.open(face_file.stream)
        style_image = Image.open(style_file.stream)
        
        # Convert to RGB if needed
        if face_image.mode != 'RGB':
            face_image = face_image.convert('RGB')
        if style_image.mode != 'RGB':
            style_image = style_image.convert('RGB')
        
        # Convert to numpy arrays
        face_array = np.array(face_image)
        style_array = np.array(style_image)
        
        # Preprocess images
        face_tensor = inference_engine.preprocess_image_from_array(face_array)
        style_tensor = inference_engine.preprocess_image_from_array(style_array)
        
        # Create face mask
        face_mask = inference_engine.create_face_mask()
        
        # Apply makeup
        result = inference_engine.apply_makeup(face_tensor, style_tensor, face_mask)
        
        # Convert result to image
        result_image = inference_engine.postprocess_image(result)
        
        # Convert to bytes
        img_buffer = io.BytesIO()
        result_image.save(img_buffer, format='JPEG', quality=95)
        img_buffer.seek(0)
        
        return send_file(
            img_buffer,
            mimetype='image/jpeg',
            as_attachment=True,
            download_name='makeup_result.jpg'
        )
        
    except Exception as e:
        print(f"Error in apply_makeup: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/makeup_styles', methods=['GET'])
def get_makeup_styles():
    """Get available makeup styles"""
    styles = [
        {
            'id': 'natural',
            'name': 'Natural Look',
            'image_url': '/static/styles/natural.jpg',
            'category': 'everyday'
        },
        {
            'id': 'dramatic',
            'name': 'Dramatic Eye',
            'image_url': '/static/styles/dramatic.jpg',
            'category': 'evening'
        },
        {
            'id': 'vintage',
            'name': 'Vintage Glam',
            'image_url': '/static/styles/vintage.jpg',
            'category': 'special'
        },
        {
            'id': 'smoky',
            'name': 'Smoky Eye',
            'image_url': '/static/styles/smoky.jpg',
            'category': 'evening'
        }
    ]
    
    return jsonify({'styles': styles})

@app.route('/api/process_face', methods=['POST'])
def process_face():
    """Process face image for analysis"""
    try:
        if 'face_image' not in request.files:
            return jsonify({'error': 'No face image provided'}), 400
        
        face_file = request.files['face_image']
        face_image = Image.open(face_file.stream)
        
        if face_image.mode != 'RGB':
            face_image = face_image.convert('RGB')
        
        # Convert to numpy array
        face_array = np.array(face_image)
        
        # Detect face landmarks (simplified)
        landmarks = detect_face_landmarks(face_array)
        
        # Create face mask
        face_mask = create_face_mask_from_landmarks(face_array, landmarks)
        
        # Return processed data
        return jsonify({
            'landmarks': landmarks.tolist() if landmarks is not None else [],
            'face_detected': landmarks is not None,
            'face_mask_created': face_mask is not None
        })
        
    except Exception as e:
        print(f"Error in process_face: {e}")
        return jsonify({'error': str(e)}), 500

def detect_face_landmarks(image):
    """Detect face landmarks (simplified implementation)"""
    # This is a placeholder - in practice, you'd use a proper face landmark detector
    # like dlib, MediaPipe, or MTCNN
    
    # For now, return None to indicate no landmarks detected
    # In a real implementation, you would:
    # 1. Use a face detection model to find faces
    # 2. Use a landmark detection model to find key points
    # 3. Return the landmark coordinates
    
    return None

def create_face_mask_from_landmarks(image, landmarks):
    """Create face mask from landmarks"""
    if landmarks is None:
        return None
    
    # Create mask based on landmarks
    # This is a simplified implementation
    mask = np.zeros(image.shape[:2], dtype=np.uint8)
    
    # In practice, you would create a proper mask using the landmark points
    # to define the face region
    
    return mask

if __name__ == '__main__':
    print("Initializing Virtual Try-On Makeup API...")
    
    try:
        initialize_model()
        print("Model loaded successfully!")
        
        # Create static directory for style images
        os.makedirs('static/styles', exist_ok=True)
        
        # Start the Flask app
        app.run(
            host='0.0.0.0',
            port=8000,
            debug=True
        )
        
    except Exception as e:
        print(f"Failed to initialize model: {e}")
        print("Starting API without model (some endpoints will not work)")
        app.run(
            host='0.0.0.0',
            port=8000,
            debug=True
        )

