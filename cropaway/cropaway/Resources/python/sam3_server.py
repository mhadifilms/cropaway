#!/usr/bin/env python3
"""
SAM3 HTTP Server for Cropaway.
Provides REST API for image segmentation using SAM (Segment Anything Model).
"""

import os
import sys
import base64
import io
import json
import argparse
from typing import Optional

from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image
import numpy as np

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sam3_inference import get_predictor, unload_predictor, SAM3Predictor
from mask_utils import mask_to_base64, base64_to_mask, get_bounding_box

app = Flask(__name__)
CORS(app)

# Global state
predictor: Optional[SAM3Predictor] = None
model_loaded = False
current_model_id = "facebook/sam-vit-huge"


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        "status": "ok",
        "model_loaded": model_loaded,
        "model_id": current_model_id if model_loaded else None
    })


@app.route('/initialize', methods=['POST'])
def initialize():
    """
    Initialize/load the SAM model.

    Request body:
    {
        "model_id": "facebook/sam-vit-huge"  // optional, defaults to sam-vit-huge
    }
    """
    global predictor, model_loaded, current_model_id

    try:
        data = request.get_json() or {}
        model_id = data.get('model_id', 'facebook/sam-vit-huge')

        # Unload existing model if different
        if predictor is not None and current_model_id != model_id:
            unload_predictor()
            predictor = None
            model_loaded = False

        # Load model
        if not model_loaded:
            predictor = get_predictor(model_id)
            success = predictor.load_model()

            if success:
                model_loaded = True
                current_model_id = model_id
                return jsonify({
                    "status": "ok",
                    "message": f"Model {model_id} loaded successfully"
                })
            else:
                return jsonify({
                    "status": "error",
                    "message": "Failed to load model"
                }), 500
        else:
            return jsonify({
                "status": "ok",
                "message": "Model already loaded"
            })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/unload', methods=['POST'])
def unload():
    """Unload the model to free memory."""
    global predictor, model_loaded

    try:
        unload_predictor()
        predictor = None
        model_loaded = False

        return jsonify({
            "status": "ok",
            "message": "Model unloaded"
        })
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/segment/points', methods=['POST'])
def segment_with_points():
    """
    Segment image using point prompts.

    Request body:
    {
        "image": "base64_encoded_image",
        "points": [[0.5, 0.3], [0.6, 0.4]],  // normalized coordinates
        "labels": [1, 1]  // 1 = foreground, 0 = background
    }

    Response:
    {
        "status": "ok",
        "mask": "base64_rle_encoded",
        "bounding_box": {"x": 0.2, "y": 0.1, "width": 0.4, "height": 0.5},
        "confidence": 0.95,
        "object_id": "obj_1_abc12345"
    }
    """
    global predictor, model_loaded

    if not model_loaded or predictor is None:
        return jsonify({
            "status": "error",
            "message": "Model not loaded. Call /initialize first."
        }), 400

    try:
        data = request.get_json()

        if not data:
            return jsonify({
                "status": "error",
                "message": "No JSON data provided"
            }), 400

        # Decode image
        image_b64 = data.get('image')
        if not image_b64:
            return jsonify({
                "status": "error",
                "message": "No image provided"
            }), 400

        image_bytes = base64.b64decode(image_b64)
        image = Image.open(io.BytesIO(image_bytes))

        # Get points and labels
        points = data.get('points', [])
        labels = data.get('labels', [])

        if not points:
            return jsonify({
                "status": "error",
                "message": "No points provided"
            }), 400

        if len(points) != len(labels):
            return jsonify({
                "status": "error",
                "message": "Points and labels must have same length"
            }), 400

        # Set image and predict
        predictor.set_image(image)
        result = predictor.predict_with_points(
            points=[tuple(p) for p in points],
            labels=labels
        )

        return jsonify({
            "status": "ok",
            "mask": result["mask_base64"],
            "bounding_box": result["bounding_box"],
            "confidence": result["confidence"],
            "object_id": result["object_id"]
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/segment/box', methods=['POST'])
def segment_with_box():
    """
    Segment image using bounding box prompt.

    Request body:
    {
        "image": "base64_encoded_image",
        "box": {"x": 0.2, "y": 0.1, "width": 0.4, "height": 0.5}  // normalized
    }
    """
    global predictor, model_loaded

    if not model_loaded or predictor is None:
        return jsonify({
            "status": "error",
            "message": "Model not loaded. Call /initialize first."
        }), 400

    try:
        data = request.get_json()

        if not data:
            return jsonify({
                "status": "error",
                "message": "No JSON data provided"
            }), 400

        # Decode image
        image_b64 = data.get('image')
        if not image_b64:
            return jsonify({
                "status": "error",
                "message": "No image provided"
            }), 400

        image_bytes = base64.b64decode(image_b64)
        image = Image.open(io.BytesIO(image_bytes))

        # Get box
        box_data = data.get('box')
        if not box_data:
            return jsonify({
                "status": "error",
                "message": "No box provided"
            }), 400

        box = (
            box_data.get('x', 0),
            box_data.get('y', 0),
            box_data.get('width', 1),
            box_data.get('height', 1)
        )

        # Set image and predict
        predictor.set_image(image)
        result = predictor.predict_with_box(box=box)

        return jsonify({
            "status": "ok",
            "mask": result["mask_base64"],
            "bounding_box": result["bounding_box"],
            "confidence": result["confidence"],
            "object_id": result["object_id"]
        })

    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/segment/text', methods=['POST'])
def segment_with_text():
    """
    Segment image using text prompt.
    Note: Requires SAM3 or text-capable model variant.

    Request body:
    {
        "image": "base64_encoded_image",
        "prompt": "the yellow bus"
    }
    """
    global predictor, model_loaded

    if not model_loaded or predictor is None:
        return jsonify({
            "status": "error",
            "message": "Model not loaded. Call /initialize first."
        }), 400

    try:
        data = request.get_json()

        if not data:
            return jsonify({
                "status": "error",
                "message": "No JSON data provided"
            }), 400

        # Decode image
        image_b64 = data.get('image')
        if not image_b64:
            return jsonify({
                "status": "error",
                "message": "No image provided"
            }), 400

        image_bytes = base64.b64decode(image_b64)
        image = Image.open(io.BytesIO(image_bytes))

        # Get text prompt
        prompt = data.get('prompt')
        if not prompt:
            return jsonify({
                "status": "error",
                "message": "No text prompt provided"
            }), 400

        # Set image and predict
        predictor.set_image(image)
        result = predictor.predict_with_text(text_prompt=prompt)

        return jsonify({
            "status": "ok",
            "mask": result["mask_base64"],
            "bounding_box": result["bounding_box"],
            "confidence": result["confidence"],
            "object_id": result["object_id"]
        })

    except NotImplementedError as e:
        return jsonify({
            "status": "error",
            "message": str(e),
            "hint": "Text prompts require SAM3 model. Use point or box prompts instead."
        }), 501
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/models', methods=['GET'])
def list_models():
    """List available SAM models."""
    return jsonify({
        "status": "ok",
        "models": [
            {
                "id": "facebook/sam-vit-base",
                "name": "SAM Base",
                "size": "~375MB",
                "description": "Fastest, good for quick inference"
            },
            {
                "id": "facebook/sam-vit-large",
                "name": "SAM Large",
                "size": "~1.2GB",
                "description": "Balanced speed and quality"
            },
            {
                "id": "facebook/sam-vit-huge",
                "name": "SAM Huge",
                "size": "~2.5GB",
                "description": "Best quality, slowest"
            }
        ],
        "current_model": current_model_id if model_loaded else None
    })


def main():
    parser = argparse.ArgumentParser(description='SAM3 Segmentation Server')
    parser.add_argument('--port', type=int, default=8765, help='Port to run server on')
    parser.add_argument('--host', type=str, default='127.0.0.1', help='Host to bind to')
    parser.add_argument('--model', type=str, default='facebook/sam-vit-huge',
                        help='Model ID to load on startup')
    parser.add_argument('--preload', action='store_true',
                        help='Preload model on startup')
    args = parser.parse_args()

    print(f"Starting SAM3 Server on {args.host}:{args.port}")

    if args.preload:
        print(f"Preloading model: {args.model}")
        global predictor, model_loaded, current_model_id
        predictor = get_predictor(args.model)
        if predictor.load_model():
            model_loaded = True
            current_model_id = args.model
            print("Model preloaded successfully")
        else:
            print("Warning: Failed to preload model")

    app.run(host=args.host, port=args.port, threaded=True)


if __name__ == '__main__':
    main()
