#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TEMPO L3 NetCDF -> JSON (coarse 0.1° grid) converter — CLEAN & SAFE
- Normalize longitudes to [-180, 180) and reorder columns accordingly
- Align latitude (lat) direction with data array
- Build coarse axes from the native fine axes (block-mean over lat/lon)
- Apply CLDO4 cloud mask resampled onto the coarse grid (co-registered with the product)
- **Hard value sanitization**: drop NaN/Inf, invalid negatives, and unrealistic outliers

Example run:
  ./.venv/bin/python py/tempo_to_json.py --product=no2 \
    --in-root=storage/app/tempo --grid=0.1 --cloud-th=0.3 --keep-hours=72
"""

import argparse
import json
import math
import os
import re
import sys
import traceback
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

try:
    import numpy as np
except Exception:
    print("ERROR: numpy is required. pip install numpy", file=sys.stderr)
    raise

try:
    from netCDF4 import Dataset
except Exception:
    print("ERROR: netCDF4 is required. pip install netCDF4", file=sys.stderr)
    raise


# ---------- Constants & Product Map ----------

PRODUCTS = {
    "no2":   {"var": "product/vertical_column_troposphere", "unit_hint": "molec/cm2", "uses_cloud": True,  "allow_zero": False, "hard_min": 0.0,     "hard_max": 5e16},
    "hcho":  {"var": "product/vertical_column",             "unit_hint": "molec/cm2", "uses_cloud": True,  "allow_zero": False, "hard_min": 0.0,     "hard_max": 3e16},
    "o3tot": {"var": "product/column_amount_o3",            "unit_hint": "DU",        "uses_cloud": True,  "allow_zero": True,  "hard_min": 0.0,     "hard_max": 700.0},
    "cldo4": {"var": "product/cloud_fraction",              "unit_hint": "fraction",  "uses_cloud": False, "allow_zero": True,  "hard_min": 0.0,     "hard_max": 1.0},
}

LAT_CANDIDATES = ["latitude", "geolocation/latitude"]
LON_CANDIDATES = ["longitude", "geolocation/longitude"]

ABSURD_NEG = -1e20  # anything less than this → NaN
ABSURD_POS =  1e20  # anything greater than this for molecule/DU units → NaN


# ---------- Utility helpers ----------

def now_utc_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso8601(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        if s.endswith("Z"):
            return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def mid_time_iso(t0: Optional[str], t1: Optional[str]) -> Optional[str]:
    d0 = parse_iso8601(t0) if t0 else None
    d1 = parse_iso8601(t1) if t1 else None
    if d0 and d1:
        mid = d0 + (d1 - d0) / 2
        return mid.strftime("%Y-%m-%dT%H:%M:%SZ")
    return t1 or t0


def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)


def read_json(path: str) -> Optional[dict]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def write_json_atomic(path: str, payload: dict):
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    os.replace(tmp, path)


def product_paths(in_root: str, product: str) -> Tuple[str, str]:
    pdir = os.path.join(in_root, product)
    jdir = os.path.join(pdir, "json")
    return pdir, jdir


def nc_path_for_gid(product_dir: str, product: str, gid: str) -> str:
    return os.path.join(product_dir, f"{product}_{gid}.nc")


def json_path_for_gid(json_dir: str, product: str, gid: str) -> str:
    return os.path.join(json_dir, f"{product}_{gid}.json")


def extract_gid_from_filename(fn: str) -> Optional[str]:
    m = re.search(r"_(G[0-9A-Z\-]+-LARC_CLOUD)\.json$", fn)
    return m.group(1) if m else None


def load_input_index(in_root: str, product: str) -> Dict[str, dict]:
    pdir, _ = product_paths(in_root, product)
    idx_path = os.path.join(pdir, "index.json")
    js = read_json(idx_path) or {}
    if not isinstance(js, dict):
        return {}
    return js


def time_overlap_score(a0: Optional[str], a1: Optional[str], b0: Optional[str], b1: Optional[str]) -> float:
    da0, da1, db0, db1 = map(parse_iso8601, (a0, a1, b0, b1))
    if not (da0 and da1 and db0 and db1):
        return -1e9
    latest_start = max(da0, db0)
    earliest_end = min(da1, db1)
    overlap = (earliest_end - latest_start).total_seconds()
    if overlap > 0:
        return overlap
    gap = (latest_start - earliest_end).total_seconds()
    return -gap


def select_best_cldo4(in_root: str, target_t0: Optional[str], target_t1: Optional[str]) -> Optional[Tuple[str, dict]]:
    cld_idx = load_input_index(in_root, "cldo4")
    best_gid, best_meta, best_score = None, None, -1e12
    for gid, meta in cld_idx.items():
        t0 = (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[0]
        t1 = (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[-1]
        score = time_overlap_score(target_t0, target_t1, t0, t1)
        if score > best_score:
            best_score, best_gid, best_meta = score, gid, meta
    return (best_gid, best_meta) if best_gid else None


# ---------- NetCDF helpers ----------

def _get_var_by_path(ds: Dataset, path: str):
    parts = path.split("/")
    obj = ds
    for p in parts[:-1]:
        if hasattr(obj, "groups") and p in obj.groups:
            obj = obj.groups[p]
        else:
            raise KeyError(f"Group '{p}' not found for path '{path}'")
    varname = parts[-1]
    if hasattr(obj, "variables") and varname in obj.variables:
        return obj.variables[varname]
    raise KeyError(f"Variable '{varname}' not found for path '{path}'")


def read_axis(ds: Dataset, candidates: List[str]) -> np.ndarray:
    for name in candidates:
        try:
            v = _get_var_by_path(ds, name)
            return np.array(v[...])
        except Exception:
            continue
    raise KeyError(f"None of the axis candidates found: {candidates}")


def read_main_array(ds: Dataset, var_path: str) -> Tuple[np.ndarray, str]:
    v = _get_var_by_path(ds, var_path)
    units = getattr(v, "units", "") or ""
    data = np.array(v[...], dtype=np.float64)
    if data.ndim == 3 and data.shape[0] == 1:
        data = data[0]
    return data, units


def axes_from_latlon(lat: np.ndarray, lon: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    lat_arr = np.array(lat)
    lon_arr = np.array(lon)
    if lat_arr.ndim == 2 and lon_arr.ndim == 2:
        lat_1d = np.nanmean(lat_arr, axis=1)
        lon_1d = np.nanmean(lon_arr, axis=0)
    else:
        lat_1d = lat_arr.ravel()
        lon_1d = lon_arr.ravel()
    return np.array(lat_1d, dtype=float), np.array(lon_1d, dtype=float)


def infer_step(vec: np.ndarray) -> float:
    v = np.asarray(vec).ravel()
    diffs = np.diff(v)
    diffs = diffs[np.isfinite(diffs)]
    if diffs.size == 0:
        raise ValueError("Cannot infer step from empty diffs")
    return float(np.nanmedian(np.abs(diffs)))


def normalize_lon_and_align(lon1d: np.ndarray,
                            arr2d: np.ndarray,
                            also_return_order: bool = False):
    lon_norm = ((lon1d.astype(float) + 180.0) % 360.0) - 180.0
    order = np.argsort(lon_norm)
    lon_sorted = lon_norm[order]
    if arr2d.ndim != 2 or arr2d.shape[1] != lon1d.size:
        raise ValueError("arr2d must be (H,W) aligned with lon (W).")
    arr_sorted = arr2d[:, order]
    if also_return_order:
        return lon_sorted, arr_sorted, order
    return lon_sorted, arr_sorted


def block_reduce_mean(arr: np.ndarray, by_y: int, by_x: int) -> np.ndarray:
    h, w = arr.shape
    H = (h // by_y) * by_y
    W = (w // by_x) * by_x
    if H == 0 or W == 0:
        raise ValueError(f"Block size too large for data shape {arr.shape}")
    d = arr[:H, :W].reshape(H // by_y, by_y, W // by_x, by_x)
    return np.nanmean(np.nanmean(d, axis=3), axis=1)


def reindex_to(lat_src: np.ndarray, lon_src: np.ndarray, src: np.ndarray,
               lat_dst: np.ndarray, lon_dst: np.ndarray) -> np.ndarray:
    iy = np.searchsorted(lat_src, lat_dst)
    ix = np.searchsorted(lon_src, lon_dst)
    iy = np.clip(iy, 0, len(lat_src)-1)
    ix = np.clip(ix, 0, len(lon_src)-1)
    return src[iy[:, None], ix[None, :]]


# ---------- Core conversion ----------

def _sanitize_array_for_product(arr: np.ndarray, product: str) -> np.ndarray:
    """Hard sanitization per product (NaN/Inf/negatives/outliers/clamp to logical range)."""
    spec = PRODUCTS[product]
    allow_zero = spec["allow_zero"]
    hard_min   = spec["hard_min"]
    hard_max   = spec["hard_max"]

    A = arr.astype(float, copy=True)

    # NaN/Inf → NaN
    A[~np.isfinite(A)] = np.nan

    # Remove extreme outliers
    A[A < ABSURD_NEG] = np.nan
    A[A > ABSURD_POS] = np.nan

    # Logical minimum (for most products negative values are invalid)
    if not allow_zero:
        A[A <= 0.0] = np.nan
    else:
        A[A < hard_min] = hard_min  # e.g., CLDO4 minimum is 0
    # Logical maximum
    A[A > hard_max] = hard_max

    return A


def convert_nc_to_json(
    in_root: str,
    product: str,
    gid: str,
    grid_deg: float = 0.1,
    cloud_th: Optional[float] = 0.3,
    dry_run: bool = False,
    verbose: bool = False,
) -> Optional[Tuple[str, int]]:
    pdir, jdir = product_paths(in_root, product)
    ensure_dir(jdir)

    nc_path = nc_path_for_gid(pdir, product, gid)
    if not os.path.isfile(nc_path):
        if verbose:
            print(f"[{product}] NC not found for {gid}: {nc_path}")
        return None

    # Times from input index
    inp_idx = load_input_index(in_root, product)
    meta = inp_idx.get(gid, {})
    t0 = (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[0]
    t1 = (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[-1]
    issued = mid_time_iso(t0, t1) or now_utc_iso()

    # Read data and axes
    with Dataset(nc_path, mode="r") as ds:
        arr, units_from_nc = read_main_array(ds, PRODUCTS[product]["var"])
        lat_raw = read_axis(ds, LAT_CANDIDATES)
        lon_raw = read_axis(ds, LON_CANDIDATES)

    arr = np.squeeze(arr)
    if arr.ndim != 2:
        if verbose:
            print(f"[{product}] Unexpected data ndim={arr.ndim} for {gid}, skipping.")
        return None

    lat1d, lon1d = axes_from_latlon(lat_raw, lon_raw)

    # Latitude direction: if descending, reverse both axis and data
    if lat1d[0] > lat1d[-1]:
        lat1d = lat1d[::-1]
        arr = arr[::-1, :]

    # Normalize longitude and reorder columns
    lon1d, arr = normalize_lon_and_align(lon1d, arr)

    # Compute native step and block factors
    try:
        dlat = infer_step(lat1d)
        dlon = infer_step(lon1d)
    except Exception:
        dlat = dlon = 0.02

    by_y = max(1, int(round(grid_deg / max(1e-12, abs(dlat)))))
    by_x = max(1, int(round(grid_deg / max(1e-12, abs(dlon)))))

    # Safe edge trimming and block reduction
    h, w = arr.shape
    Hc = (h // by_y) * by_y
    Wc = (w // by_x) * by_x
    if Hc == 0 or Wc == 0:
        if verbose:
            print(f"[{product}] grid factors too large for shape {arr.shape}", file=sys.stderr)
        return None

    arr_trim = arr[:Hc, :Wc]
    coarse = block_reduce_mean(arr_trim, by_y, by_x).astype(np.float64)

    # Coarse axes derived from native axes
    lat_c = lat1d[:Hc].reshape(Hc // by_y, by_y).mean(axis=1)
    lon_c = lon1d[:Wc].reshape(Wc // by_x, by_x).mean(axis=1)

    # Cloud mask (if enabled and product is not the cloud itself)
    if PRODUCTS[product]["uses_cloud"] and cloud_th is not None and cloud_th >= 0:
        sel = select_best_cldo4(in_root, t0, t1)
        if sel:
            cld_gid, _ = sel
            cld_dir, _ = product_paths(in_root, "cldo4")
            cld_path = nc_path_for_gid(cld_dir, "cldo4", cld_gid)
            if os.path.isfile(cld_path):
                with Dataset(cld_path, mode="r") as cds:
                    cf_raw, _u = read_main_array(cds, PRODUCTS["cldo4"]["var"])
                    cf_raw = np.squeeze(cf_raw)
                    latc_raw = read_axis(cds, LAT_CANDIDATES)
                    lonc_raw = read_axis(cds, LON_CANDIDATES)
                    latc1, lonc1 = axes_from_latlon(latc_raw, lonc_raw)
                    if latc1[0] > latc1[-1]:
                        latc1 = latc1[::-1]
                        cf_raw = cf_raw[::-1, :]
                    lonc1, cf_raw = normalize_lon_and_align(lonc1, cf_raw)
                    cf_on_product = reindex_to(latc1, lonc1, cf_raw, lat_c, lon_c)
                    # **Sanitize CF into [0..1]**
                    cf_on_product = np.clip(cf_on_product, 0.0, 1.0)
                    coarse = np.where(cf_on_product > float(cloud_th), np.nan, coarse)

    # **Hard sanitization based on product constraints**
    coarse = _sanitize_array_for_product(coarse, product)

    # bbox from coarse axes
    south = float(np.nanmin(lat_c)); north = float(np.nanmax(lat_c))
    west  = float(np.nanmin(lon_c)); east  = float(np.nanmax(lon_c))

    Hout, Wout = coarse.shape
    lat_list = np.asarray(lat_c).round(6).tolist()
    lon_list = np.asarray(lon_c).round(6).tolist()

    units = units_from_nc or PRODUCTS[product]["unit_hint"]

    # **Output uses None (not NaN)**
    payload = {
        "product": product,
        "source_gid": gid,
        "issued_at": issued,
        "subset_time": [t0, t1],
        "bbox": [round(south, 6), round(north, 6), round(west, 6), round(east, 6)],
        "grid_deg": float(grid_deg),
        "origin": [round(south, 6), round(west, 6)],
        "shape": [int(Hout), int(Wout)],
        "unit": units,
        "cloud_th": float(cloud_th) if (PRODUCTS[product]["uses_cloud"] and cloud_th is not None) else None,
        "lat": lat_list,
        "lon": lon_list,
        "data": [[(None if (not math.isfinite(x)) else float(round(float(x), 6))) for x in row] for row in coarse.tolist()],
    }

    out_path = json_path_for_gid(jdir, product, gid)
    if dry_run:
        if verbose:
            print(f"[{product}] DRY-RUN would write: {out_path} ({Hout}x{Wout})")
        return None

    ensure_dir(jdir)
    write_json_atomic(out_path, payload)
    nbytes = os.path.getsize(out_path)
    if verbose:
        print(f"[{product}] Wrote {out_path} ({nbytes} bytes)")
    return out_path, nbytes


def sync_product(
    in_root: str,
    product: str,
    grid_deg: float = 0.1,
    cloud_th: float = 0.3,
    keep_hours: int = 72,
    dry_run: bool = False,
    limit: Optional[int] = None,
    verbose: bool = False,
) -> int:
    pdir, jdir = product_paths(in_root, product)
    ensure_dir(jdir)

    inp_idx = load_input_index(in_root, product)
    wanted_gids = list(inp_idx.keys())

    if limit is not None and limit > 0:
        wanted_gids = wanted_gids[:limit]

    done = 0
    for gid in wanted_gids:
        out_path = json_path_for_gid(jdir, product, gid)
        if os.path.isfile(out_path):
            continue
        try:
            r = convert_nc_to_json(
                in_root=in_root,
                product=product,
                gid=gid,
                grid_deg=grid_deg,
                cloud_th=(None if cloud_th is not None and cloud_th < 0 else cloud_th),
                dry_run=dry_run,
                verbose=verbose,
            )
            if r:
                done += 1
        except Exception as e:
            if verbose:
                print(f"[{product}] ERROR converting {gid}: {e}")
                traceback.print_exc()

    # Remove JSONs that are no longer present in the input index
    existing = [f for f in os.listdir(jdir) if f.endswith(".json") and f != "index.json"]
    to_remove = []
    for fn in existing:
        gid2 = extract_gid_from_filename(fn)
        if gid2 and gid2 not in inp_idx:
            to_remove.append(os.path.join(jdir, fn))

    for p in to_remove:
        if dry_run:
            if verbose:
                print(f"[{product}] DRY-RUN would remove stale JSON: {p}")
        else:
            try:
                os.remove(p)
                if verbose:
                    print(f"[{product}] Removed stale JSON: {p}")
            except Exception as e:
                if verbose:
                    print(f"[{product}] Failed to remove {p}: {e}")

    # Build output json/index.json under json/
    out_index: Dict[str, dict] = {}
    for gid, meta in inp_idx.items():
        fn = os.path.basename(json_path_for_gid(jdir, product, gid))
        out_file = os.path.join(jdir, fn)
        if os.path.isfile(out_file):
            try:
                sz = os.path.getsize(out_file)
            except Exception:
                sz = None
            out_index[gid] = {
                "file": fn,
                "bytes": sz,
                "t0": (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[0],
                "t1": (meta.get("subset_time") or [meta.get("t0"), meta.get("t1")])[-1],
                "saved": now_utc_iso(),
                "grid_deg": float(grid_deg),
            }

    if not dry_run:
        write_json_atomic(os.path.join(jdir, "index.json"), out_index)
        if verbose:
            print(f"[{product}] Updated JSON index with {len(out_index)} items.")

    return done


# ---------- CLI ----------

def main():
    ap = argparse.ArgumentParser(description="TEMPO L3 NC -> JSON converter (per product)")
    ap.add_argument("--product", choices=list(PRODUCTS.keys()), required=True, help="no2|hcho|o3tot|cldo4")
    ap.add_argument("--in-root", default="storage/app/tempo", help="Input storage root (Laravel)")
    ap.add_argument("--grid", type=float, default=0.1, help="Target grid degree for coarse JSON")
    ap.add_argument("--cloud-th", type=float, default=0.3, help="Cloud fraction threshold (>0 enables, <0 disables)")
    ap.add_argument("--keep-hours", type=int, default=72, help="Hours to keep (compat with cron)")
    ap.add_argument("--limit", type=int, default=0, help="Limit number of granules (testing)")
    ap.add_argument("--dry-run", action="store_true", help="Do not write files; just simulate")
    ap.add_argument("--verbose", action="store_true", help="Verbose logs")
    ap.add_argument("--self-check", action="store_true", help="Quick environment/self check and exit")
    args = ap.parse_args()

    if args.self_check:
        import netCDF4
        print("Self-check:")
        print(f"  Python : {sys.version.split()[0]}")
        print(f"  numpy  : {np.__version__}")
        print(f"  netCDF4: {netCDF4.__version__}")
        root = os.path.abspath(args.in_root)
        print(f"  in-root: {root}  exists={os.path.isdir(root)}")
        for p in PRODUCTS.keys():
            pdir, jdir = product_paths(args.in_root, p)
            print(f"  {p:6s}  in={os.path.isdir(pdir)}  json_out={jdir}")
        sys.exit(0)

    limit = args.limit if args.limit and args.limit > 0 else None
    try:
        n = sync_product(
            in_root=args.in_root,
            product=args.product,
            grid_deg=args.grid,
            cloud_th=args.cloud_th,
            keep_hours=args.keep_hours,
            dry_run=args.dry_run,
            limit=limit,
            verbose=args.verbose,
        )
        if args.verbose:
            print(f"[{args.product}] Converted {n} granule(s).")
    except KeyboardInterrupt:
        print("Interrupted.")
        sys.exit(130)
    except Exception as e:
        print(f"FATAL: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
