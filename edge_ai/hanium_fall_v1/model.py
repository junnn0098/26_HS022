"""1D-CNN used by the team for the report's fall-detection results.

The layer names and shapes must stay identical to the team checkpoints
(`weights/*.pth`); any change breaks `load_state_dict`.
"""

from __future__ import annotations

import torch.nn as nn

IN_CHANNELS = 134
FRAMES = 500
FALL_INDEX = 0  # softmax[:, 0] is the fall probability, softmax[:, 1] is non-fall


class CSI1DCNN(nn.Module):
    """Input (batch, 134, 500) -> logits (batch, 2). About 66k parameters."""

    def __init__(self, in_channels: int = IN_CHANNELS, num_classes: int = 2, width: int = 32):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(in_channels, width, 7, padding=3),
            nn.BatchNorm1d(width), nn.ReLU(), nn.MaxPool1d(2),
            nn.Conv1d(width, width * 2, 5, padding=2),
            nn.BatchNorm1d(width * 2), nn.ReLU(), nn.MaxPool1d(2),
            nn.Conv1d(width * 2, width * 4, 3, padding=1),
            nn.BatchNorm1d(width * 4), nn.ReLU(), nn.AdaptiveAvgPool1d(1),
        )
        self.head = nn.Linear(width * 4, num_classes)

    def forward(self, x):
        return self.head(self.features(x).squeeze(-1))


def parameter_count(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters())
