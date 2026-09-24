"""Rebuild disposable Frigate labels from the deployed YOLO ONNX metadata.

The model owns class order. Never retain an older label map merely because it
exists. Validate the model before atomically replacing the derived file.
"""
import ast
import os
from pathlib import Path
import sys
import tempfile

import onnx


def model_labels(model_path):
    model = onnx.load(model_path, load_external_data=False)
    metadata = {item.key: item.value for item in model.metadata_props}
    names = ast.literal_eval(metadata["names"])
    if not isinstance(names, dict) or set(names) != set(range(len(names))):
        raise ValueError("LABEL_IDS: model class IDs must be contiguous integers")
    channels = model.graph.output[0].type.tensor_type.shape.dim[1].dim_value
    if channels != len(names) + 4:
        raise ValueError("LABEL_COUNT: YOLO output and model names disagree")
    labels = [names[i] for i in range(len(names))]
    if any(not isinstance(s, str) or not s or "\n" in s or "\r" in s for s in labels):
        raise ValueError("LABEL_TEXT: invalid class name")
    return labels


def write_labels(model_path, destination):
    labels = model_labels(model_path)
    destination = Path(destination)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent,
                                         prefix=".labels-", delete=False) as out:
            temporary = out.name
            out.write("\n".join(labels) + "\n")
            out.flush()
            os.fsync(out.fileno())
            os.fchmod(out.fileno(), 0o644)
        os.replace(temporary, destination)
        temporary = None
    finally:
        if temporary is not None:
            os.unlink(temporary)


if __name__ == "__main__":
    write_labels(sys.argv[1], sys.argv[2])
