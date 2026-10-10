"""Mask-aware multi-task temporal model for LLTF64 room-level CSI sensing.

The 193 channels are 64 absolute log-amplitude, 64 dynamic-amplitude,
64 phase-delta, and one RSSI channel.  Keep ``node_mask``: it changes no model
parameter shapes and safely excludes a temporarily absent receiver.
"""

from __future__ import annotations

import torch
from torch import nn


class ResidualTemporalBlock(nn.Module):
    def __init__(self, input_channels: int, output_channels: int, stride: int = 1) -> None:
        super().__init__()
        self.main = nn.Sequential(
            nn.Conv1d(input_channels, output_channels, 5, stride=stride, padding=2, bias=False),
            nn.GroupNorm(8, output_channels),
            nn.GELU(),
            nn.Conv1d(output_channels, output_channels, 3, padding=1, bias=False),
            nn.GroupNorm(8, output_channels),
        )
        self.skip = (
            nn.Identity()
            if input_channels == output_channels and stride == 1
            else nn.Conv1d(input_channels, output_channels, 1, stride=stride, bias=False)
        )
        self.activation = nn.GELU()

    def forward(self, values: torch.Tensor) -> torch.Tensor:
        return self.activation(self.main(values) + self.skip(values))


class NodeEncoder(nn.Module):
    def __init__(self, feature_channels: int, embedding_dim: int, dropout: float) -> None:
        super().__init__()
        self.network = nn.Sequential(
            nn.Conv1d(feature_channels, 64, 7, stride=2, padding=3, bias=False),
            nn.GroupNorm(8, 64),
            nn.GELU(),
            ResidualTemporalBlock(64, 64),
            ResidualTemporalBlock(64, 96, stride=2),
            ResidualTemporalBlock(96, 128, stride=2),
            nn.AdaptiveAvgPool1d(1),
            nn.Flatten(),
            nn.Dropout(dropout),
            nn.Linear(128, embedding_dim),
            nn.LayerNorm(embedding_dim),
            nn.GELU(),
        )

    def forward(self, values: torch.Tensor) -> torch.Tensor:
        return self.network(values)


class MultiNodeFallModel(nn.Module):
    """Shared node encoder plus activity, person count, and quality heads."""

    def __init__(
        self,
        feature_channels: int = 193,
        embedding_dim: int = 128,
        activity_classes: int = 10,
        count_classes: int = 4,
        dropout: float = 0.20,
    ) -> None:
        super().__init__()
        self.feature_channels = feature_channels
        self.embedding_dim = embedding_dim
        self.activity_classes = activity_classes
        self.count_classes = count_classes
        self.node_encoder = NodeEncoder(feature_channels, embedding_dim, dropout)
        self.attention = nn.Sequential(
            nn.Linear(embedding_dim + 1, 64),
            nn.GELU(),
            nn.Linear(64, 1),
        )
        fused_dim = embedding_dim + 1
        self.activity_head = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(fused_dim, embedding_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(embedding_dim, activity_classes),
        )
        self.count_head = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(fused_dim, 64),
            nn.GELU(),
            nn.Linear(64, count_classes),
        )
        self.quality_head = nn.Sequential(nn.Linear(fused_dim, 1), nn.Sigmoid())

    def forward(
        self,
        features: torch.Tensor,
        node_mask: torch.Tensor,
        node_quality: torch.Tensor,
    ) -> dict[str, torch.Tensor]:
        if features.ndim != 4:
            raise ValueError("features must be (batch, nodes, channels, time)")
        batch, nodes, channels, frames = features.shape
        if channels != self.feature_channels:
            raise ValueError(f"feature channels={channels}, expected={self.feature_channels}")
        encoded = self.node_encoder(features.reshape(batch * nodes, channels, frames))
        encoded = encoded.reshape(batch, nodes, self.embedding_dim)
        quality_column = node_quality.unsqueeze(-1)
        attention_logits = self.attention(torch.cat([encoded, quality_column], dim=-1)).squeeze(-1)
        attention_logits = attention_logits.masked_fill(~node_mask.bool(), -1e4)
        attention_weights = torch.softmax(attention_logits, dim=1)
        fused_embedding = torch.sum(encoded * attention_weights.unsqueeze(-1), dim=1)
        fused_quality = torch.sum(node_quality * attention_weights, dim=1, keepdim=True)
        fused = torch.cat([fused_embedding, fused_quality], dim=1)
        return {
            "activity_logits": self.activity_head(fused),
            "count_logits": self.count_head(fused),
            "quality": self.quality_head(fused).squeeze(-1),
            "node_attention": attention_weights,
        }


def model_from_checkpoint(checkpoint: dict, device: torch.device) -> MultiNodeFallModel:
    from .fall_checkpoint import state_dict_from_payload

    config = checkpoint["model_config"]
    model = MultiNodeFallModel(**config)
    state_dict, _source = state_dict_from_payload(checkpoint)
    if state_dict is None:
        raise ValueError("checkpoint does not contain a usable model state_dict")
    model.load_state_dict(state_dict)
    model.to(device)
    model.eval()
    return model
