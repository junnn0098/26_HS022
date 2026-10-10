"""Small variable-node classifier for cough versus overnight confounders."""

from __future__ import annotations

import torch
from torch import nn

from .model import NodeEncoder


class MultiNodeCoughModel(nn.Module):
    def __init__(
        self,
        feature_channels: int = 193,
        embedding_dim: int = 96,
        classes: int = 9,
        dropout: float = 0.20,
    ) -> None:
        super().__init__()
        self.feature_channels = feature_channels
        self.classes = classes
        self.node_encoder = NodeEncoder(feature_channels, embedding_dim, dropout)
        self.node_score = nn.Linear(embedding_dim, 1)
        self.head = nn.Sequential(
            nn.LayerNorm(embedding_dim),
            nn.Linear(embedding_dim, embedding_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(embedding_dim, classes),
        )

    def forward(
        self,
        features: torch.Tensor,
        node_mask: torch.Tensor,
        node_quality: torch.Tensor,
    ) -> torch.Tensor:
        if features.ndim != 4:
            raise ValueError("features must be (batch, nodes, channels, time)")
        batch, nodes, channels, frames = features.shape
        if channels != self.feature_channels:
            raise ValueError(f"feature channels={channels}, expected={self.feature_channels}")
        encoded = self.node_encoder(features.reshape(batch * nodes, channels, frames))
        encoded = encoded.reshape(batch, nodes, -1)
        scores = self.node_score(encoded).squeeze(-1)
        scores = scores + torch.log(node_quality.clamp_min(1e-4))
        scores = scores.masked_fill(~node_mask, -1e9)
        all_missing = ~node_mask.any(dim=1)
        if bool(all_missing.any()):
            scores = scores.clone()
            scores[all_missing, 0] = 0.0
        weights = torch.softmax(scores, dim=1)
        fused = torch.sum(encoded * weights.unsqueeze(-1), dim=1)
        return self.head(fused)


def cough_model_from_checkpoint(checkpoint: dict, device: torch.device) -> MultiNodeCoughModel:
    model = MultiNodeCoughModel(**checkpoint["model_config"])
    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(device)
    model.eval()
    return model

