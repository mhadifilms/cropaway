"""
Mask utilities for RLE encoding/decoding and mask operations.
"""

import numpy as np
from typing import Tuple, Optional
import base64
import zlib


def mask_to_rle(mask: np.ndarray) -> bytes:
    """
    Convert binary mask to Run-Length Encoded (RLE) bytes.

    Args:
        mask: Binary mask as numpy array (H, W), values 0 or 1/255

    Returns:
        RLE encoded bytes (zlib compressed)
    """
    # Ensure binary mask
    if mask.max() > 1:
        mask = (mask > 127).astype(np.uint8)
    else:
        mask = mask.astype(np.uint8)

    # Flatten the mask
    flat = mask.flatten()

    # Find run lengths
    if len(flat) == 0:
        return zlib.compress(b'')

    # Pad to handle edge cases
    padded = np.concatenate([[0], flat, [0]])

    # Find where values change
    changes = np.where(padded[1:] != padded[:-1])[0]

    # Calculate run lengths
    run_lengths = np.diff(changes)

    # First value tells us if we start with 0 or 1
    start_value = flat[0]

    # Encode as bytes: [start_value, height(2), width(2), num_runs(4), run_lengths...]
    height, width = mask.shape
    header = bytes([start_value])
    header += height.to_bytes(2, 'little')
    header += width.to_bytes(2, 'little')
    header += len(run_lengths).to_bytes(4, 'little')

    # Run lengths as uint16 (max 65535 per run)
    runs_bytes = b''
    for rl in run_lengths:
        # Handle runs longer than 65535
        while rl > 65535:
            runs_bytes += (65535).to_bytes(2, 'little')
            runs_bytes += (0).to_bytes(2, 'little')  # Zero-length run of opposite value
            rl -= 65535
        runs_bytes += int(rl).to_bytes(2, 'little')

    data = header + runs_bytes
    return zlib.compress(data)


def rle_to_mask(rle_bytes: bytes) -> Optional[np.ndarray]:
    """
    Convert RLE encoded bytes back to binary mask.

    Args:
        rle_bytes: RLE encoded bytes (zlib compressed)

    Returns:
        Binary mask as numpy array (H, W) with values 0 or 255
    """
    try:
        data = zlib.decompress(rle_bytes)
        if len(data) < 9:
            return None

        # Parse header
        start_value = data[0]
        height = int.from_bytes(data[1:3], 'little')
        width = int.from_bytes(data[3:5], 'little')
        num_runs = int.from_bytes(data[5:9], 'little')

        # Parse run lengths
        run_lengths = []
        offset = 9
        for _ in range(num_runs):
            if offset + 2 > len(data):
                break
            rl = int.from_bytes(data[offset:offset+2], 'little')
            run_lengths.append(rl)
            offset += 2

        # Reconstruct mask
        flat = np.zeros(height * width, dtype=np.uint8)
        current_value = start_value
        pos = 0

        for rl in run_lengths:
            if pos + rl > len(flat):
                rl = len(flat) - pos
            if rl > 0:
                flat[pos:pos+rl] = current_value * 255
                pos += rl
            current_value = 1 - current_value

        return flat.reshape(height, width)
    except Exception as e:
        print(f"Error decoding RLE: {e}")
        return None


def mask_to_base64(mask: np.ndarray) -> str:
    """
    Convert binary mask to base64-encoded RLE string.
    """
    rle_bytes = mask_to_rle(mask)
    return base64.b64encode(rle_bytes).decode('utf-8')


def base64_to_mask(b64_string: str) -> Optional[np.ndarray]:
    """
    Convert base64-encoded RLE string back to binary mask.
    """
    try:
        rle_bytes = base64.b64decode(b64_string)
        return rle_to_mask(rle_bytes)
    except Exception as e:
        print(f"Error decoding base64 mask: {e}")
        return None


def get_bounding_box(mask: np.ndarray) -> Tuple[float, float, float, float]:
    """
    Get normalized bounding box from binary mask.

    Returns:
        (x, y, width, height) normalized to 0-1 range
    """
    if mask.max() == 0:
        return (0.0, 0.0, 1.0, 1.0)

    # Find non-zero pixels
    rows = np.any(mask > 0, axis=1)
    cols = np.any(mask > 0, axis=0)

    if not np.any(rows) or not np.any(cols):
        return (0.0, 0.0, 1.0, 1.0)

    y_min, y_max = np.where(rows)[0][[0, -1]]
    x_min, x_max = np.where(cols)[0][[0, -1]]

    h, w = mask.shape

    # Normalize to 0-1
    return (
        float(x_min) / w,
        float(y_min) / h,
        float(x_max - x_min + 1) / w,
        float(y_max - y_min + 1) / h
    )


def resize_mask(mask: np.ndarray, target_size: Tuple[int, int]) -> np.ndarray:
    """
    Resize binary mask to target size using nearest neighbor interpolation.

    Args:
        mask: Binary mask (H, W)
        target_size: (width, height) tuple

    Returns:
        Resized binary mask
    """
    from PIL import Image

    # Convert to PIL Image
    img = Image.fromarray(mask)

    # Resize using nearest neighbor to preserve binary values
    resized = img.resize(target_size, Image.NEAREST)

    return np.array(resized)


def combine_masks(masks: list, weights: Optional[list] = None) -> np.ndarray:
    """
    Combine multiple masks into one.

    Args:
        masks: List of binary masks
        weights: Optional confidence weights for each mask

    Returns:
        Combined binary mask
    """
    if not masks:
        raise ValueError("No masks to combine")

    if weights is None:
        weights = [1.0] * len(masks)

    # Weighted sum
    combined = np.zeros_like(masks[0], dtype=np.float32)
    for mask, weight in zip(masks, weights):
        combined += mask.astype(np.float32) * weight

    # Threshold at 0.5
    return (combined > 0.5 * sum(weights)).astype(np.uint8) * 255
