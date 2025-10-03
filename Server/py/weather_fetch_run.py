#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Weather fetch job for ClimateWise (fixed + TEMPO-aligned)
---------------------------------------------------------
- Reads grid directly from TEMPO: storage/app/tempo/no2/fc_support/latest.json
  => shape/bbox/grid_deg will match exactly (fixes shape_bbox_mismatch)
- Variables: u10, v10, blh
- Time range: +1..+12h
- Primary source: GFS 0.25° (OPeNDAP) | Fallback: Open-Meteo (single-point demo)
- Outputs hourly slices as GZIP: storage/app/weather/meteo/json/<run_id>/+Hh.json.gz
- index.json contains shape/bbox/grid_deg and is kept in sync with TEMPO
- Keeps only the latest KEEP_RUNS runs
"""

import os, sys, json, shutil, datetime, platform, gzip
from pathlib import Path

print("PY:", sys.executable, "VER:", platform.python_version(), flush=True)

import numpy as np
try:
    import xarray as xr   # for GFS netCDF
    import requests
except ImportError:
    print("You need: pip install xarray netCDF4 requests")
    sys.exit(1)

# ---------------- PATHS / CONFIG ----------------
TEMPO_LATEST = Path("storage/app/tempo/no2/fc_support/latest.json")
OUT_BASE     = Path("storage/app/weather/meteo/json")
HOURS        = list(range(1, 13))
KEEP_RUNS    = 3
BLH0_M       = 800.0  # fallback BLH (m) if not available from GFS
# ------------------------------------------------

def read_tempo_grid():
    """
    Read the TEMPO grid: shape=[H,W], bbox=[S,N,W,E], grid_deg.
    Then build exactly H×W coordinates with linspace so that edges line up.
    """
    if not TEMPO_LATEST.is_file():
        raise FileNotFoundError(f"{TEMPO_LATEST} not found")
    js = json.load(open(TEMPO_LATEST))
    shape = js.get("shape")
    bbox  = js.get("bbox")
    grid  = float(js.get("grid_deg", 0.1))
    if (not isinstance(shape, list) or len(shape) != 2 or
        not isinstance(bbox, list)  or len(bbox)  != 4):
        raise ValueError("TEMPO latest.json missing valid shape/bbox")

    H, W = int(shape[0]), int(shape[1])
    S, N, Wdeg, Edeg = map(float, bbox)
    # linspace => exactly H and W points (including edges)
    lats = np.linspace(S, N, H)
    lons = np.linspace(Wdeg, Edeg, W)
    return dict(shape=[H, W], bbox=[S, N, Wdeg, Edeg], grid_deg=grid, lats=lats, lons=lons)

def fetch_from_gfs(hours, lats, lons, shape, bbox, grid_deg):
    """
    Fetch from GFS 0.25° (OPeNDAP)
    - u10, v10 are guaranteed.
    - blh: try common variable names as availability differs across datasets.
    """
    cycle = datetime.datetime.utcnow().replace(minute=0, second=0, microsecond=0)
    cycle = cycle - datetime.timedelta(hours=cycle.hour % 6)  # nearest 6-hourly cycle
    ymd = cycle.strftime("%Y%m%d")
    hhz = cycle.strftime("%H")
    url = f"https://nomads.ncep.noaa.gov:9090/dods/gfs_0p25/gfs{ymd}/gfs_0p25_{hhz}z"

    try:
        ds = xr.open_dataset(url)
    except Exception as e:
        print(f"GFS fetch failed: {e}")
        return None, None

    try:
        u10 = ds['u10']
        v10 = ds['v10']
    except Exception as e:
        print(f"GFS dataset missing vars u10/v10: {e}")
        return None, None

    # Attempt to find BLH (names vary between dataset versions)
    blh_var = None
    for cand in ['blh', 'hgtbl', 'hgtbls', 'hpbl', 'pblh']:
        if cand in ds.variables:
            blh_var = ds[cand]
            break

    out = {}
    for h in hours:
        step = h  # +H hours after cycle
        try:
            u = u10.isel(time=step).interp(lat=lats, lon=lons).values
            v = v10.isel(time=step).interp(lat=lats, lon=lons).values
            if blh_var is not None:
                bl = blh_var.isel(time=step).interp(lat=lats, lon=lons).values
                bl = np.maximum(0.0, np.nan_to_num(bl))
            else:
                bl = np.full((shape[0], shape[1]), BLH0_M)
        except Exception as e:
            print(f"GFS interp failed for +{h}h: {e}")
            continue

        valid_time = (cycle + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ")
        out[h] = dict(
            product="wind10",
            grid_deg=float(grid_deg),
            bbox=bbox,
            shape=shape,
            unit={"u10": "m/s", "v10": "m/s", "blh": "m"},
            t_offset=f"+{h}h",
            valid_time=valid_time,
            u10=np.round(u, 2).tolist(),
            v10=np.round(v, 2).tolist(),
            blh=np.round(bl, 1).tolist(),
        )
    return out, cycle.strftime("%Y-%m-%dT%H:%M:%SZ")

def fetch_from_openmeteo(hours, lats, lons, shape, bbox, grid_deg):
    """
    Simple fallback: Open-Meteo (single central point → fill the entire grid uniformly).
    - Only to keep the pipeline running and preserve JSON structure.
    """
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        "latitude": 40, "longitude": -100,  # arbitrary central point
        "hourly": "windspeed_10m,winddirection_10m",
        "forecast_days": 1,
    }

    try:
        r = requests.get(url, params=params, timeout=30)
        r.raise_for_status()
        js = r.json()
        spd = js["hourly"]["windspeed_10m"]
        dire = js["hourly"]["winddirection_10m"]
    except Exception as e:
        print(f"Open-Meteo fetch failed: {e}")
        return None

    now = datetime.datetime.utcnow().replace(minute=0, second=0, microsecond=0)
    H, W = shape
    out = {}

    for h in hours:
        idx = h if h < len(spd) else -1
        try:
            speed = float(spd[idx])
            direction = float(dire[idx])
            rad = np.deg2rad(direction)
            # Convert speed/direction to U/V components (meteorological convention)
            # u = -speed * sin(dir), v = -speed * cos(dir)
            u = -speed * np.sin(rad)
            v = -speed * np.cos(rad)
        except Exception:
            u = v = 0.0

        valid_time = (now + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M:%SZ")
        out[h] = dict(
            product="wind10",
            grid_deg=float(grid_deg),
            bbox=bbox,
            shape=shape,
            unit={"u10": "m/s", "v10": "m/s", "blh": "m"},
            t_offset=f"+{h}h",
            valid_time=valid_time,
            u10=np.round(np.full((H, W), u), 2).tolist(),
            v10=np.round(np.full((H, W), v), 2).tolist(),
            blh=np.round(np.full((H, W), BLH0_M), 1).tolist(),
        )
    return out

def write_json_gz(path: Path, obj: dict):
    """Write JSON as gzip to reduce file size."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wt", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)

def cleanup_runs(base: Path, keep: int):
    runs = sorted([d for d in base.iterdir() if d.is_dir()], reverse=True)
    for old in runs[keep:]:
        shutil.rmtree(old, ignore_errors=True)

def main():
    OUT_BASE.mkdir(parents=True, exist_ok=True)

    # 1) Read grid from TEMPO
    tg = read_tempo_grid()
    shape = tg["shape"]; bbox = tg["bbox"]; grid_deg = tg["grid_deg"]
    lats  = tg["lats"];  lons = tg["lons"]

    # 2) run_id
    run_id = datetime.datetime.utcnow().replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")
    run_dir = OUT_BASE / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    # 3) Try GFS → then fallback
    slices, cycle = fetch_from_gfs(HOURS, lats, lons, shape, bbox, grid_deg)
    source = "GFS-0p25 OPeNDAP"
    fallback = False

    if not slices:
        print("Falling back to Open-Meteo…")
        slices = fetch_from_openmeteo(HOURS, lats, lons, shape, bbox, grid_deg)
        source = "Open-Meteo"
        cycle = run_id
        fallback = True

    if not slices:
        print("Weather fetch failed completely")
        sys.exit(1)

    # 4) Save slices (GZIP): +Hh.json.gz
    for h, data in slices.items():
        write_json_gz(run_dir / f"+{h}h.json.gz", data)

    # 5) index.json with TEMPO-aligned shape/bbox
    index = dict(
        latest_run=run_id,
        hours=HOURS,
        grid_deg=float(grid_deg),
        bbox=bbox,
        shape=shape,
        source=source,
        cycle=cycle,
        fallback=fallback,
    )
    with open(OUT_BASE / "index.json", "w") as f:
        json.dump(index, f, ensure_ascii=False)

    # 6) Cleanup older runs
    cleanup_runs(OUT_BASE, KEEP_RUNS)

    print(f"Weather run {run_id} complete, source={source}, fallback={fallback}")
    print(f"Grid: shape={shape}, bbox={bbox}, grid_deg={grid_deg}")

if __name__ == "__main__":
    main()
