#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_tempo_forecast_summaries.py — CLEAN & SAFE (NaN→None + timezone-aware)
- latest.json: last valid value per cell + data age (hours)
- hod/: hourly-of-day (0..23) mean over the product grid
- Hard cleanup: drop NaN/Inf/invalid negatives/outliers before computation
- JSON-safe: convert all NaN/Inf to None before json.dump
- datetimes: timezone-aware (UTC)

Run:
  ./.venv/bin/python py/build_tempo_forecast_summaries.py \
    --product no2 --in-root storage/app/tempo --hours 72 --min-per-hour 2
"""

import argparse
import json
import os
import sys
import time
import numpy as np
from datetime import datetime, timezone
from typing import Dict, Any, List, Tuple, Optional

ISO_FMT = "%Y-%m-%dT%H:%M:%SZ"

# Same reasonable limits used in tempo_to_json
SPEC = {
    "no2":   {"allow_zero": False, "min": 0.0, "max": 5e16},
    "hcho":  {"allow_zero": False, "min": 0.0, "max": 3e16},
    "o3tot": {"allow_zero": True,  "min": 0.0, "max": 700.0},
    "cldo4": {"allow_zero": True,  "min": 0.0, "max": 1.0},
}
ABSURD_NEG = -1e20
ABSURD_POS =  1e20


def parse_iso8601(ts: str) -> Optional[int]:
    if not ts:
        return None
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return int(datetime.fromisoformat(ts).timestamp())
    except Exception:
        try:
            if "." in ts:
                base, rest = ts.split(".", 1)
                tz = ""
                if "+" in rest:
                    tz = "+" + rest.split("+", 1)[1]
                elif "-" in rest[1:]:
                    dash_pos = rest[1:].find("-")
                    if dash_pos >= 0:
                        tz = "-" + rest[1 + dash_pos + 1:]
                ts2 = base + tz
                if ts2.endswith("Z"):
                    ts2 = ts2[:-1] + "+00:00"
                return int(datetime.fromisoformat(ts2).timestamp())
        except Exception:
            return None
        return None


def load_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def compute_local_hour(utc_end_ts: int, lon_deg_2d: np.ndarray) -> np.ndarray:
    offset_sec = (lon_deg_2d / 360.0) * 86400.0
    local_ts = utc_end_ts + offset_sec
    local_hour = np.floor(local_ts / 3600.0) % 24.0
    return local_hour.astype(np.int16)


def to_float_grid(a) -> np.ndarray:
    return np.array(a, dtype=float)


def sanitize_grid(grid: np.ndarray, product: str) -> np.ndarray:
    spec = SPEC.get(product, {"allow_zero": False, "min": 0.0, "max": 1.0})
    allow_zero = spec["allow_zero"]
    g = grid.astype(float, copy=True)
    g[~np.isfinite(g)] = np.nan
    g[g < ABSURD_NEG] = np.nan
    g[g > ABSURD_POS] = np.nan
    if not allow_zero:
        g[g <= 0.0] = np.nan
    else:
        g[g < spec["min"]] = spec["min"]
    g[g > spec["max"]] = spec["max"]
    return g


def jsonable_2d(arr: np.ndarray, ndigits: int = 6) -> list:
    """
    np.ndarray -> nested Python list, with:
    - rounding
    - NaN/±Inf -> None (JSON-safe)
    """
    a = np.asarray(arr, dtype=float)
    if ndigits is not None:
        a = np.round(a, decimals=ndigits)   # fixed
    out = a.astype(object)
    mask = ~np.isfinite(a)
    if mask.any():
        out[mask] = None
    return out.tolist()


def build_latest(values_stack: List[Tuple[int, np.ndarray]]) -> Tuple[np.ndarray, np.ndarray, int]:
    if not values_stack:
        raise ValueError("No granule data provided.")
    values_stack.sort(key=lambda t: t[0])  # oldest -> newest

    latest = None
    latest_ts = None
    for end_ts, grid in values_stack:
        if latest is None:
            latest = grid.copy()
            latest_ts = np.full_like(latest, fill_value=float(end_ts), dtype=float)
        else:
            mask_new = np.isfinite(grid)
            latest[mask_new] = grid[mask_new]
            latest_ts[mask_new] = float(end_ts)

    now_ts = time.time()
    age_h = (now_ts - latest_ts) / 3600.0
    age_h[~np.isfinite(latest)] = np.nan
    newest_end_ts = int(values_stack[-1][0])
    return latest, age_h, newest_end_ts


def build_hod(values_stack: List[Tuple[int, np.ndarray]], lon2d: np.ndarray,
              min_per_hour: int = 2):
    if not values_stack:
        raise ValueError("No granule data provided.")
    H, W = values_stack[0][1].shape
    hod_sum = [np.zeros((H, W), dtype=float) for _ in range(24)]
    hod_cnt = [np.zeros((H, W), dtype=np.int32) for _ in range(24)]
    hour_counts = [0 for _ in range(24)]

    for end_ts, grid in values_stack:
        local_hour = compute_local_hour(end_ts, lon2d)
        valid_mask = np.isfinite(grid)
        for h in range(24):
            m = valid_mask & (local_hour == h)
            if np.any(m):
                hod_sum[h][m] += grid[m]
                hod_cnt[h][m] += 1
                hour_counts[h] += 1

    hod_grids = []
    for h in range(24):
        out = np.full((H, W), np.nan, dtype=float)
        mask = hod_cnt[h] >= min_per_hour
        if np.any(mask):
            out[mask] = hod_sum[h][mask] / hod_cnt[h][mask]
        hod_grids.append(out)
    return hod_grids, hour_counts


def write_latest_json(out_path: str, meta: Dict[str, Any],
                      latest: np.ndarray, age_h: np.ndarray) -> None:
    latest_q = jsonable_2d(latest, ndigits=6)
    age_q    = jsonable_2d(age_h, ndigits=2)
    payload = {
        "product": meta.get("product"),
        "unit": meta.get("unit"),
        "grid_deg": meta.get("grid_deg"),
        "bbox": meta.get("bbox"),
        "shape": meta.get("shape"),
        "origin": "build_tempo_forecast_summaries.py",
        "generated_at": datetime.now(timezone.utc).strftime(ISO_FMT),
        "data": {"value": latest_q, "age_h": age_q}
    }
    ensure_dir(os.path.dirname(out_path))
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def write_hod_split(out_dir: str, meta: Dict[str, Any],
                    hod_grids, hour_counts):
    ensure_dir(out_dir)
    meta_payload = {
        "product": meta.get("product"),
        "unit": meta.get("unit"),
        "grid_deg": meta.get("grid_deg"),
        "bbox": meta.get("bbox"),
        "shape": meta.get("shape"),
        "origin": "build_tempo_forecast_summaries.py",
        "generated_at": datetime.now(timezone.utc).strftime(ISO_FMT),
        "hours_window": meta.get("hours_window"),
        "min_per_hour": meta.get("min_per_hour"),
        "hour_counts": hour_counts
    }
    with open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta_payload, f, ensure_ascii=False, separators=(",", ":"))

    for h in range(24):
        grid_q = jsonable_2d(hod_grids[h], ndigits=6)
        payload = {"hour": h, "data": grid_q}
        with open(os.path.join(out_dir, f"hour_{h:02d}.json"), "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--product", required=True,
                    choices=["no2", "hcho", "o3tot", "cldo4"])
    ap.add_argument("--in-root", required=True,
                    help="Root folder for tempo storage (e.g., storage/app/tempo)")
    ap.add_argument("--hours", type=int, default=72,
                    help="Window in hours to consider (default 72)")
    ap.add_argument("--min-per-hour", type=int, default=2,
                    help="Min per-cell samples required for HOD mean")
    args = ap.parse_args()

    product = args.product
    root = args.in_root
    hours_window = int(args.hours)

    prod_dir = os.path.join(root, product)
    json_dir = os.path.join(prod_dir, "json")
    index_path = os.path.join(json_dir, "index.json")

    index = load_json(index_path)
    if not isinstance(index, dict) or not index:
        sys.exit(f"Bad or empty index.json: {index_path}")

    now_ts = time.time()
    cutoff_ts = now_ts - hours_window * 3600

    # Collect granules from json index using the 'file' field directly
    granules: List[Tuple[int, str, str]] = []  # (end_ts, json_path, gid)
    for gid, meta in index.items():
        if not isinstance(meta, dict):
            continue

        t1 = meta.get("t1") or meta.get("end") or meta.get("saved")
        if not t1:
            st = meta.get("subset_time") or meta.get("subsetTime") or {}
            if isinstance(st, dict):
                t1 = st.get("end") or st.get("t1")
        end_ts = parse_iso8601(t1) if isinstance(t1, str) else None
        if end_ts is None or end_ts < cutoff_ts:
            continue

        file_rel = meta.get("file")
        if not isinstance(file_rel, str) or not file_rel.endswith(".json"):
            file_rel = f"{product}_{gid}.json"
        json_path = os.path.join(json_dir, os.path.basename(file_rel))
        if not os.path.isfile(json_path):
            json_path2 = os.path.join(json_dir, file_rel)
            if os.path.isfile(json_path2):
                json_path = json_path2
            else:
                continue

        granules.append((end_ts, json_path, gid))

    if not granules:
        sys.exit("No granules found in window (check time parsing and index->file mapping).")

    granules.sort(key=lambda t: t[0])

    # Infer grid from first granule
    first = load_json(granules[0][1])
    if not first or "data" not in first:
        sys.exit(f"Cannot read first granule json: {granules[0][1]}")
    data0 = to_float_grid(first["data"])
    H, W = data0.shape

    lat = first.get("lat")
    lon = first.get("lon")
    bbox = first.get("bbox")
    grid_deg = first.get("grid_deg")
    unit = first.get("unit")

    if lon is None:
        if not bbox or grid_deg is None:
            sys.exit("Missing lon and bbox/grid_deg in granule json.")
        W_, E = float(bbox[2]), float(bbox[3])
        lon = np.linspace(W_, E, W, dtype=float)
    else:
        lon = np.array(lon, dtype=float)

    if np.ndim(lon) == 1:
        lon2d = np.tile(lon.reshape(1, W), (H, 1))
    elif np.ndim(lon) == 2:
        lon2d = lon
    else:
        sys.exit("Unexpected lon array dimensionality.")

    # Load and sanitize all grids
    values_stack: List[Tuple[int, np.ndarray]] = []
    newest_gid = None
    newest_end_ts = None

    for end_ts, jpath, gid in granules:
        g = load_json(jpath)
        if not g or "data" not in g:
            continue
        grid = to_float_grid(g["data"])
        if grid.shape != (H, W):
            continue
        grid = sanitize_grid(grid, product)
        values_stack.append((end_ts, grid))
        newest_gid = gid
        newest_end_ts = end_ts

    if not values_stack:
        sys.exit("No usable grids found after loading.")

    latest_grid, age_grid, newest_end_ts2 = build_latest(values_stack)
    if newest_end_ts is None:
        newest_end_ts = newest_end_ts2
    hod_grids, hour_counts = build_hod(values_stack, lon2d, min_per_hour=args.min_per_hour)

    # Sanitize HOD as well (clamp/None)
    hod_grids = [sanitize_grid(hg, product) for hg in hod_grids]

    fc_dir = os.path.join(prod_dir, "fc_support")
    meta_common = {
        "product": product,
        "unit": unit,
        "grid_deg": grid_deg,
        "bbox": bbox,
        "shape": [H, W],
        "hours_window": hours_window,
        "min_per_hour": args.min_per_hour,
        "newest_gid": newest_gid,
        "newest_end": (datetime.fromtimestamp(newest_end_ts, timezone.utc).strftime(ISO_FMT)
                       if newest_end_ts else None),
    }
    write_latest_json(os.path.join(fc_dir, "latest.json"), meta_common, latest_grid, age_grid)
    write_hod_split(os.path.join(fc_dir, "hod"), meta_common, hod_grids, hour_counts)
    # print("Summaries written:", os.path.join(fc_dir, "latest.json"), os.path.join(fc_dir, "hod"))


if __name__ == "__main__":
    main()
