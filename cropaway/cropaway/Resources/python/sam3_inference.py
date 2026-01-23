"""
SAM3 (Segment Anything Model 3) inference wrapper.
Supports point prompts, box prompts, and text prompts.
"""

import torch
import numpy as np
from PIL import Image
from typing import List, Tuple, Optional, Dict, Any
import uuid

# Try to import transformers for SAM3
try:
    from transformers import SamModel, SamProcessor
    HAS_SAM = True
except ImportError:
    HAS_SAM = False
    print("Warning: transformers not installed. Run: pip install git+https://github.com/huggingface/transformers")


class SAM3Predictor:
    """
    Wrapper for SAM3 model inference.
    """

    def __init__(self, model_id: str = "facebook/sam-vit-huge", device: str = None):
        """
        Initialize SAM3 predictor.

        Args:
            model_id: HuggingFace model ID
            device: Device to use ('cpu', 'cuda', or 'mps')
        """
        if not HAS_SAM:
            raise RuntimeError("transformers library not installed")

        # Determine device
        if device is None:
            if torch.backends.mps.is_available():
                device = "mps"
            elif torch.cuda.is_available():
                device = "cuda"
            else:
                device = "cpu"

        self.device = device
        self.model_id = model_id
        self.model = None
        self.processor = None
        self.current_image = None
        self.current_embedding = None
        self._object_counter = 0

    def load_model(self) -> bool:
        """
        Load the SAM model and processor.

        Returns:
            True if successful
        """
        try:
            print(f"Loading SAM model: {self.model_id}")
            print(f"Using device: {self.device}")

            self.processor = SamProcessor.from_pretrained(self.model_id)
            self.model = SamModel.from_pretrained(self.model_id)

            # Move to device
            if self.device == "mps":
                # MPS has some limitations, use float32
                self.model = self.model.to(self.device)
            elif self.device == "cuda":
                self.model = self.model.to(self.device).half()
            else:
                self.model = self.model.to(self.device)

            self.model.eval()
            print("Model loaded successfully")
            return True

        except Exception as e:
            print(f"Error loading model: {e}")
            return False

    def set_image(self, image: Image.Image) -> bool:
        """
        Set the current image for segmentation.
        Precomputes image embeddings for faster subsequent predictions.

        Args:
            image: PIL Image

        Returns:
            True if successful
        """
        if self.model is None:
            raise RuntimeError("Model not loaded")

        try:
            self.current_image = image.convert("RGB")
            # We'll compute embeddings on-demand with prompts
            self.current_embedding = None
            return True
        except Exception as e:
            print(f"Error setting image: {e}")
            return False

    def predict_with_points(
        self,
        points: List[Tuple[float, float]],
        labels: List[int],
        multimask_output: bool = True
    ) -> Dict[str, Any]:
        """
        Predict mask from point prompts.

        Args:
            points: List of (x, y) coordinates in normalized [0, 1] range
            labels: List of labels (1 for foreground, 0 for background)
            multimask_output: Whether to return multiple masks

        Returns:
            Dictionary with mask, bounding box, confidence, and object ID
        """
        if self.current_image is None:
            raise RuntimeError("No image set")

        # Convert normalized points to pixel coordinates
        w, h = self.current_image.size
        pixel_points = [[int(x * w), int(y * h)] for x, y in points]

        # Prepare inputs
        inputs = self.processor(
            self.current_image,
            input_points=[pixel_points],
            input_labels=[labels],
            return_tensors="pt"
        )

        # Move to device
        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        # Run inference
        with torch.no_grad():
            outputs = self.model(**inputs, multimask_output=multimask_output)

        # Process outputs
        masks = self.processor.image_processor.post_process_masks(
            outputs.pred_masks.cpu(),
            inputs["original_sizes"].cpu(),
            inputs["reshaped_input_sizes"].cpu()
        )[0]

        scores = outputs.iou_scores[0].cpu().numpy()

        # Select best mask
        best_idx = np.argmax(scores)
        best_mask = masks[best_idx].numpy().squeeze()
        best_score = float(scores[best_idx])

        # Convert to binary mask (0 or 255)
        binary_mask = (best_mask > 0.5).astype(np.uint8) * 255

        # Get bounding box
        from mask_utils import get_bounding_box, mask_to_base64
        bbox = get_bounding_box(binary_mask)

        # Generate object ID
        self._object_counter += 1
        object_id = f"obj_{self._object_counter}_{uuid.uuid4().hex[:8]}"

        return {
            "mask": binary_mask,
            "mask_base64": mask_to_base64(binary_mask),
            "bounding_box": {
                "x": bbox[0],
                "y": bbox[1],
                "width": bbox[2],
                "height": bbox[3]
            },
            "confidence": best_score,
            "object_id": object_id
        }

    def predict_with_box(
        self,
        box: Tuple[float, float, float, float],
        multimask_output: bool = True
    ) -> Dict[str, Any]:
        """
        Predict mask from bounding box prompt.

        Args:
            box: (x, y, width, height) in normalized [0, 1] range
            multimask_output: Whether to return multiple masks

        Returns:
            Dictionary with mask, bounding box, confidence, and object ID
        """
        if self.current_image is None:
            raise RuntimeError("No image set")

        # Convert normalized box to pixel coordinates [x_min, y_min, x_max, y_max]
        w, h = self.current_image.size
        x, y, bw, bh = box
        pixel_box = [
            int(x * w),
            int(y * h),
            int((x + bw) * w),
            int((y + bh) * h)
        ]

        # Prepare inputs
        inputs = self.processor(
            self.current_image,
            input_boxes=[[pixel_box]],
            return_tensors="pt"
        )

        # Move to device
        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        # Run inference
        with torch.no_grad():
            outputs = self.model(**inputs, multimask_output=multimask_output)

        # Process outputs
        masks = self.processor.image_processor.post_process_masks(
            outputs.pred_masks.cpu(),
            inputs["original_sizes"].cpu(),
            inputs["reshaped_input_sizes"].cpu()
        )[0]

        scores = outputs.iou_scores[0].cpu().numpy()

        # Select best mask
        best_idx = np.argmax(scores)
        best_mask = masks[best_idx].numpy().squeeze()
        best_score = float(scores[best_idx])

        # Convert to binary mask
        binary_mask = (best_mask > 0.5).astype(np.uint8) * 255

        # Get bounding box
        from mask_utils import get_bounding_box, mask_to_base64
        bbox = get_bounding_box(binary_mask)

        # Generate object ID
        self._object_counter += 1
        object_id = f"obj_{self._object_counter}_{uuid.uuid4().hex[:8]}"

        return {
            "mask": binary_mask,
            "mask_base64": mask_to_base64(binary_mask),
            "bounding_box": {
                "x": bbox[0],
                "y": bbox[1],
                "width": bbox[2],
                "height": bbox[3]
            },
            "confidence": best_score,
            "object_id": object_id
        }

    def predict_with_text(
        self,
        text_prompt: str,
        multimask_output: bool = True
    ) -> Dict[str, Any]:
        """
        Predict mask from text prompt.
        Note: Standard SAM doesn't support text prompts directly.
        This would require SAM3 or a variant with text understanding.
        For now, we'll return an error suggesting to use point prompts.

        Args:
            text_prompt: Text description of object to segment
            multimask_output: Whether to return multiple masks

        Returns:
            Dictionary with mask, bounding box, confidence, and object ID
        """
        # SAM (facebook/sam-vit-huge) doesn't support text prompts
        # This would require a model like SAM3 or Grounded-SAM
        raise NotImplementedError(
            "Text prompts require SAM3 or Grounded-SAM. "
            "Please use point or box prompts instead, or install a text-capable model."
        )

    def unload_model(self):
        """
        Unload the model to free memory.
        """
        if self.model is not None:
            del self.model
            self.model = None
        if self.processor is not None:
            del self.processor
            self.processor = None
        self.current_image = None
        self.current_embedding = None

        # Clear CUDA/MPS cache
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()


# Global predictor instance
_predictor: Optional[SAM3Predictor] = None


def get_predictor(model_id: str = "facebook/sam-vit-huge") -> SAM3Predictor:
    """
    Get or create the global predictor instance.
    """
    global _predictor
    if _predictor is None or _predictor.model_id != model_id:
        _predictor = SAM3Predictor(model_id=model_id)
    return _predictor


def unload_predictor():
    """
    Unload the global predictor instance.
    """
    global _predictor
    if _predictor is not None:
        _predictor.unload_model()
        _predictor = None
