"""Strict compatibility checks for fall/activity checkpoints.

The external no-mask model has the same trainable parameter layout as the
mask-aware RC6 model.  Its weights can therefore be reused, but live inference
must keep the node mask because real receivers can disappear temporarily.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from .labels import ACTIVITIES


CHECKPOINT_SCHEMA = "hanium.ruview.model-checkpoint.v1"
COUNT_LABELS = ("0", "1", "2", "3plus")
EXPECTED_FEATURE_CONFIG = {
    "subcarriers": 64,
    "sample_rate_hz": 32,
    "window_seconds": 5.0,
    "window_frames": 160,
    "feature_channels": 193,
    "max_nodes": 4,
}
EXPECTED_MODEL_CONFIG = {
    "feature_channels": 193,
    "embedding_dim": 128,
    "activity_classes": 10,
    "count_classes": 4,
    "dropout": 0.20,
}


def state_dict_from_payload(payload: Any) -> tuple[dict[str, Any] | None, str]:
    if not isinstance(payload, Mapping):
        return None, "unsupported"
    source = "raw_state_dict"
    candidate: Any = payload
    for key in ("model_state_dict", "state_dict"):
        value = payload.get(key)
        if isinstance(value, Mapping):
            candidate = value
            source = key
            break
    if not isinstance(candidate, Mapping) or not candidate:
        return None, "missing"
    if not all(isinstance(key, str) for key in candidate):
        return None, "invalid"
    state_dict = dict(candidate)
    if state_dict and all(key.startswith("module.") for key in state_dict):
        state_dict = {key[7:]: value for key, value in state_dict.items()}
        source += "+stripped_module_prefix"
    return state_dict, source


def _compare_config(
    actual: Any,
    expected: Mapping[str, Any],
    name: str,
    errors: list[str],
) -> None:
    if not isinstance(actual, Mapping):
        errors.append(f"missing {name}")
        return
    for key, expected_value in expected.items():
        if key not in actual:
            errors.append(f"{name}.{key} is missing")
            continue
        actual_value = actual[key]
        if isinstance(expected_value, float):
            try:
                matches = abs(float(actual_value) - expected_value) <= 1e-9
            except (TypeError, ValueError):
                matches = False
        else:
            matches = actual_value == expected_value
        if not matches:
            errors.append(
                f"{name}.{key}={actual_value!r}, expected {expected_value!r}"
            )


def validate_fall_checkpoint_payload(payload: Any, torch_module: Any) -> dict[str, Any]:
    """Return a JSON-serializable compatibility and live-readiness report."""
    from .model import MultiNodeFallModel

    errors: list[str] = []
    warnings: list[str] = []
    state_dict, state_dict_source = state_dict_from_payload(payload)
    weights_compatible = False
    if state_dict is None:
        errors.append("checkpoint does not contain a usable model state_dict")
    else:
        reference = MultiNodeFallModel(**EXPECTED_MODEL_CONFIG)
        try:
            reference.load_state_dict(state_dict, strict=True)
            weights_compatible = True
        except Exception as exc:
            errors.append(f"model_state_dict is incompatible: {exc}")

    canonical = isinstance(payload, Mapping) and "model_state_dict" in payload
    required_metadata = (
        "schema",
        "model_config",
        "feature_config",
        "activity_labels",
        "count_labels",
    )
    metadata_missing = [
        key for key in required_metadata if not isinstance(payload, Mapping) or key not in payload
    ]
    if metadata_missing:
        warnings.append("metadata required by live inference is missing: " + ", ".join(metadata_missing))

    metadata_errors: list[str] = []
    if not metadata_missing and isinstance(payload, Mapping):
        if payload.get("schema") != CHECKPOINT_SCHEMA:
            metadata_errors.append(
                f"schema={payload.get('schema')!r}, expected {CHECKPOINT_SCHEMA!r}"
            )
        _compare_config(
            payload.get("model_config"),
            EXPECTED_MODEL_CONFIG,
            "model_config",
            metadata_errors,
        )
        _compare_config(
            payload.get("feature_config"),
            EXPECTED_FEATURE_CONFIG,
            "feature_config",
            metadata_errors,
        )
        if list(payload.get("activity_labels", [])) != list(ACTIVITIES):
            metadata_errors.append(
                "activity_labels order differs from the canonical 10-class RC6 order"
            )
        if list(payload.get("count_labels", [])) != list(COUNT_LABELS):
            metadata_errors.append(
                "count_labels order differs from ('0', '1', '2', '3plus')"
            )
    errors.extend(metadata_errors)

    live_ready = weights_compatible and not metadata_missing and not metadata_errors
    smoke_test = False
    if live_ready and state_dict is not None:
        model = MultiNodeFallModel(**EXPECTED_MODEL_CONFIG)
        model.load_state_dict(state_dict, strict=True)
        model.eval()
        with torch_module.no_grad():
            features = torch_module.zeros(2, 4, 193, 160)
            node_mask = torch_module.tensor(
                [[True, True, True, True], [True, True, True, False]]
            )
            node_quality = torch_module.tensor(
                [[1.0, 0.9, 0.8, 0.7], [1.0, 0.9, 0.8, 0.0]]
            )
            output = model(features, node_mask, node_quality)
            shapes_ok = (
                tuple(output["activity_logits"].shape) == (2, 10)
                and tuple(output["count_logits"].shape) == (2, 4)
                and tuple(output["quality"].shape) == (2,)
                and tuple(output["node_attention"].shape) == (2, 4)
            )
            finite = all(torch_module.isfinite(value).all().item() for value in output.values())
            sums = output["node_attention"].sum(dim=1)
            attention_ok = torch_module.allclose(sums, torch_module.ones_like(sums))
            missing_node_zero = abs(float(output["node_attention"][1, 3])) <= 1e-6
            smoke_test = bool(shapes_ok and finite and attention_ok and missing_node_zero)
        if not smoke_test:
            errors.append("mask-aware forward smoke test failed")
            live_ready = False

    if live_ready:
        result = "PASS_FALL_CHECKPOINT_LIVE_READY"
    elif weights_compatible and metadata_missing and not metadata_errors:
        result = "PASS_WEIGHTS_COMPATIBLE_METADATA_REQUIRED"
    else:
        result = "FAIL_FALL_CHECKPOINT_INCOMPATIBLE"
    return {
        "result": result,
        "checkpoint_schema": payload.get("schema") if isinstance(payload, Mapping) else None,
        "state_dict_source": state_dict_source,
        "canonical_container": canonical,
        "weights_compatible": weights_compatible,
        "live_ready": live_ready,
        "mask_aware_smoke_test": smoke_test,
        "metadata_missing": metadata_missing,
        "warnings": warnings,
        "errors": errors,
    }


def require_live_ready_fall_checkpoint(payload: Any, torch_module: Any) -> dict[str, Any]:
    """Validate a payload and raise a concise error before live deployment."""
    report = validate_fall_checkpoint_payload(payload, torch_module)
    if not report["live_ready"]:
        details = report["errors"] or report["warnings"]
        raise ValueError(f"{report['result']}: {'; '.join(details)}")
    return report
