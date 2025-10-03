#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Stations hourly ingest (NO2, O3) for the last 3 hours:
- Primary source: AirNow (US)
- Complement: OpenAQ (non-US)
- Optional: OpenAQ backfill within the US if AirNow coverage is thin

Run: python py/stations_fetch.py
Recommended cron: at hh:10 hourly

Author: climatewise.app
"""

import os, sys, json, time, pathlib, logging, requests
from typing import Dict, Any, List, Tuple, Optional
from datetime import datetime, timedelta, timezone

# =========================
# CONFIG
# =========================

# (Per your request) API keys are hardcoded for now; in production move them to ENV/.env
OPENAQ_API_KEY = "PUT_YOUR_API_KEY_HERER"
AIRNOW_API_KEY = "PUT_YOUR_API_KEY_HERER"

# BBOXes
BBOX_NA = "-170,15,-50,75"   # North America
BBOX_US = "-125,24,-66,50"   # Continental US

# Parameters
PARAMS = ["no2", "o3"]
AIRNOW_TO_INTERNAL = {"NO2": "no2", "OZONE": "o3"}

# Paths
APP_ROOT = pathlib.Path(__file__).resolve().parents[1]
STATIONS_ROOT = APP_ROOT / "storage" / "app" / "stations"
COMMON_DIR = STATIONS_ROOT / "_common"
LOG_DIR = APP_ROOT / "py" / "logs" / "np2"
LOG_DIR.mkdir(parents=True, exist_ok=True)

# Endpoints
OPENAQ_BASE = "https://api.openaq.org/v3"
OPENAQ_LOCATIONS = f"{OPENAQ_BASE}/locations"
OPENAQ_SENSORS_HOURS = f"{OPENAQ_BASE}/sensors/{{sensor_id}}/hours"
AIRNOW_DATA = "https://www.airnowapi.org/aq/data/"

# Tunables
DISCOVERY_TTL = 24 * 3600
RETENTION_HOURS = 72
REQUEST_TIMEOUT = 60
OPENAQ_PAGE_LIMIT = 1000
ROUND_DEDUP = 4

# Runtime controls via ENV
DISABLE_OPENAQ = os.getenv("DISABLE_OPENAQ", "false").lower() in ("1", "true", "yes")
OPENAQ_MAX_SENSORS_PER_RUN = int(os.getenv("OPENAQ_MAX_SENSORS_PER_RUN", "50"))   # non-US per param
PER_HOUR_TIME_BUDGET = int(os.getenv("PER_HOUR_TIME_BUDGET", "120"))              # seconds per hour

# Optional: backfill inside the US if AirNow looks thin (per param per hour)
OPENAQ_US_BACKFILL = os.getenv("OPENAQ_US_BACKFILL", "false").lower() in ("1", "true", "yes")
US_BACKFILL_MIN_COUNT = int(os.getenv("US_BACKFILL_MIN_COUNT", "500"))  # If AirNow output for a parameter is below this, fetch OpenAQ (US) as well
US_BACKFILL_MAX_SENSORS = int(os.getenv("US_BACKFILL_MAX_SENSORS", "150"))  # US sensor cap for backfill

# =========================
# LOGGING
# =========================

logger = logging.getLogger("stations_fetch")
logger.setLevel(logging.INFO)
fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")
fh = logging.FileHandler(LOG_DIR / "stations_fetch.log", encoding="utf-8")
sh = logging.StreamHandler(sys.stdout)
fh.setFormatter(fmt); sh.setFormatter(fmt)
logger.addHandler(fh); logger.addHandler(sh)

ERR_LOG = logging.getLogger("stations_errors")
efh = logging.FileHandler(LOG_DIR / "stations_errors.log", encoding="utf-8")
efh.setFormatter(fmt); ERR_LOG.addHandler(efh); ERR_LOG.setLevel(logging.WARNING)

# =========================
# FILE UTILS
# =========================

def atomic_write_json(path: pathlib.Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    tmp.replace(path)

def load_json(path: pathlib.Path) -> Optional[Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None

def iso_hour(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%HZ")

def iso_hour_filename(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H.json")

def ensure_param_dirs(param: str):
    base = STATIONS_ROOT / param / "json"
    hours_dir = base / "hours"
    index_path = base / "index.json"
    hours_dir.mkdir(parents=True, exist_ok=True)
    return hours_dir, index_path

def cleanup_old_hours(param: str) -> None:
    hours_dir, _ = ensure_param_dirs(param)
    files = sorted(p for p in hours_dir.glob("20*.json"))
    if len(files) > RETENTION_HOURS:
        to_del = files[:len(files) - RETENTION_HOURS]
        for p in to_del:
            try:
                p.unlink()
            except Exception as e:
                ERR_LOG.warning(f"cleanup {param}: {p.name}: {e}")

def update_index(param: str) -> None:
    hours_dir, index_path = ensure_param_dirs(param)
    files = sorted(p.name for p in hours_dir.glob("20*.json"))
    hours = [fn.replace(".json", "Z") for fn in files]
    latest = hours[-1] if hours else None
    meta = load_json(index_path) or {}
    meta.update({
        "hours": hours[-RETENTION_HOURS:],
        "latestHour": latest,
        "counts": meta.get("counts", {})
    })
    atomic_write_json(index_path, meta)

# =========================
# DISCOVERY (OpenAQ locations → sensors)
# =========================

def refresh_sensors_geojson_if_needed() -> List[Dict[str, Any]]:
    COMMON_DIR.mkdir(parents=True, exist_ok=True)
    geojson_path = COMMON_DIR / "sensors.geojson"
    st = None
    try:
        st = geojson_path.stat()
    except FileNotFoundError:
        pass

    need_refresh = (st is None) or ((time.time() - st.st_mtime) > DISCOVERY_TTL)
    if not need_refresh:
        gj = load_json(geojson_path)
        if gj and isinstance(gj.get("features"), list):
            return gj["features"]

    logger.info("Refreshing sensors.geojson via OpenAQ locations …")
    headers = {"X-API-Key": OPENAQ_API_KEY}
    page = 1
    features: List[Dict[str, Any]] = []

    while True:
        params = {"bbox": BBOX_NA, "page": page, "limit": OPENAQ_PAGE_LIMIT}
        try:
            r = requests.get(OPENAQ_LOCATIONS, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
        except Exception as e:
            ERR_LOG.error(f"OpenAQ locations page {page} error: {e}")
            break
        if r.status_code != 200:
            ERR_LOG.warning(f"OpenAQ locations page {page} HTTP {r.status_code}: {r.text[:200]}")
            break

        payload = r.json()
        results = payload.get("results") or []
        if not results:
            break

        for loc in results:
            coords = (loc.get("coordinates") or {})
            lat, lon = coords.get("latitude"), coords.get("longitude")
            if lat is None or lon is None:
                continue
            sensors = loc.get("sensors") or []
            for s in sensors:
                param = ((s.get("parameter") or {}).get("name") or "").lower()
                if param not in PARAMS:
                    continue
                features.append({
                    "type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [float(lon), float(lat)]},
                    "properties": {
                        "sensorsId": s.get("id"),
                        "locationsId": loc.get("id"),
                        "name": loc.get("name"),
                        "parameter": param,
                        "units": (s.get("parameter") or {}).get("units"),
                        "provider": (loc.get("provider") or {}).get("name"),
                        "timezone": loc.get("timezone"),
                        "datetimeFirst": (loc.get("datetimeFirst") or {}).get("utc"),
                        "datetimeLast": (loc.get("datetimeLast") or {}).get("utc"),
                        "country": ((loc.get("country") or {}).get("code")),
                    }
                })

        logger.info(f"OpenAQ locations page {page} parsed: +{len(results)} locations; sensors so far: {len(features)}")
        page += 1
        if len(results) < OPENAQ_PAGE_LIMIT:
            break

    # Keep only sensors active within the last 72 hours
    cutoff = datetime.now(timezone.utc) - timedelta(hours=RETENTION_HOURS)
    active = []
    for ft in features:
        last = ft["properties"].get("datetimeLast")
        if not last:
            continue
        try:
            last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
        except Exception:
            continue
        if last_dt >= cutoff:
            active.append(ft)

    geojson = {"type": "FeatureCollection", "features": active}
    atomic_write_json(geojson_path, geojson)
    logger.info(f"Wrote sensors.geojson with {len(active)} active NO2/O3 sensors")
    return active

def pick_openaq_sensor_ids(features: List[Dict[str, Any]], param: str, *, country_filter: Optional[str], limit: int) -> List[int]:
    ids = []
    for ft in features:
        prop = ft.get("properties") or {}
        if (prop.get("parameter") or "").lower() != param:
            continue
        country = (prop.get("country") or "").upper()
        if country_filter == "non-US" and country == "US":
            continue
        if country_filter == "US" and country != "US":
            continue
        sid = prop.get("sensorsId")
        if sid:
            ids.append(int(sid))
    ids = sorted(set(ids))
    return ids[:limit]

# =========================
# FETCHERS
# =========================

def fetch_airnow_hour(hour_start: datetime, bbox: str, parameters_csv: str) -> List[Dict[str, Any]]:
    start_str = hour_start.strftime("%Y-%m-%dT%H")
    end_str = (hour_start + timedelta(hours=1)).strftime("%Y-%m-%dT%H")
    params = {
        "startDate": start_str, "endDate": end_str,
        "parameters": parameters_csv, "BBOX": bbox,
        "dataType": "A", "format": "application/json",
        "API_KEY": AIRNOW_API_KEY, "includerawconcentrations": 1,
    }
    try:
        r = requests.get(AIRNOW_DATA, params=params, timeout=REQUEST_TIMEOUT)
    except Exception as e:
        ERR_LOG.warning(f"AirNow request error: {e}"); return []
    if r.status_code != 200:
        ERR_LOG.warning(f"AirNow HTTP {r.status_code}: {r.text[:200]}"); return []
    try:
        arr = r.json()
        if not isinstance(arr, list):
            ERR_LOG.warning("AirNow returned non-list JSON"); return []
    except Exception as e:
        ERR_LOG.warning(f"AirNow JSON decode error: {e}"); return []
    ts_iso = hour_start.replace(tzinfo=timezone.utc).isoformat().replace("+00:00","Z")
    out = []
    for item in arr:
        parameter = item.get("Parameter")
        if parameter not in AIRNOW_TO_INTERNAL:
            continue
        internal = AIRNOW_TO_INTERNAL[parameter]
        if internal not in PARAMS:
            continue
        lat, lon = item.get("Latitude"), item.get("Longitude")
        if lat is None or lon is None:
            continue
        units = (item.get("Unit") or "PPB").upper()
        value = item.get("RawConcentration", item.get("Concentration"))
        if value is None:
            continue
        try:
            value = float(value)
        except Exception:
            continue
        out.append({
            "ts": ts_iso, "parameter": internal, "value": value, "units": units,
            "lat": float(lat), "lon": float(lon), "provider": "AirNow",
        })
    return out

def fetch_openaq_hours_for_sensors(sensor_ids: List[int], hour_start: datetime) -> List[Dict[str, Any]]:
    headers = {"X-API-Key": OPENAQ_API_KEY}
    date_from = hour_start.replace(tzinfo=timezone.utc).isoformat().replace("+00:00","Z")
    date_to = (hour_start + timedelta(hours=1)).replace(tzinfo=timezone.utc).isoformat().replace("+00:00","Z")
    out: List[Dict[str, Any]] = []
    for i, sid in enumerate(sensor_ids, 1):
        url = OPENAQ_SENSORS_HOURS.format(sensor_id=sid)
        params = {"date_from": date_from, "date_to": date_to, "limit": OPENAQ_PAGE_LIMIT}
        try:
            r = requests.get(url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
        except Exception as e:
            ERR_LOG.warning(f"OpenAQ sensors/{sid}/hours error: {e}"); continue
        if r.status_code != 200:
            ERR_LOG.info(f"OpenAQ sensors/{sid}/hours HTTP {r.status_code}: {r.text[:160]}"); continue
        payload = r.json()
        for row in payload.get("results", []):
            val = row.get("value")
            param_obj = row.get("parameter") or {}
            param = (param_obj.get("name") or "").lower()
            units = (param_obj.get("units") or "").upper()
            coords = row.get("coordinates") or {}
            lat, lon = coords.get("latitude"), coords.get("longitude")
            if param not in PARAMS or val is None or lat is None or lon is None:
                continue
            try:
                value = float(val)
            except Exception:
                continue
            if units == "PPM":  # normalize ppm → ppb
                value *= 1000.0
                units = "PPB"
            out.append({
                "ts": date_from, "parameter": param, "value": value, "units": units or "PPB",
                "lat": float(lat), "lon": float(lon), "provider": "OpenAQ",
            })
        if i % 25 == 0:
            logger.info(f"OpenAQ progress: {i}/{len(sensor_ids)} sensors for hour {date_from}")
    return out

# =========================
# MERGE & SAVE
# =========================

def dedup_merge_pref_airnow(records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    best: Dict[Tuple[str,str,float,float], Dict[str,Any]] = {}
    for rec in records:
        key = (rec["ts"], rec["parameter"],
               round(float(rec["lat"]), ROUND_DEDUP),
               round(float(rec["lon"]), ROUND_DEDUP))
        cur = best.get(key)
        if cur is None:
            best[key] = rec
        else:
            # Prefer AirNow over OpenAQ when both exist for the same cell/time/parameter
            if cur.get("provider") == "OpenAQ" and rec.get("provider") == "AirNow":
                best[key] = rec
    return list(best.values())

def save_hour(param: str, hour_start: datetime, records: List[Dict[str, Any]]) -> None:
    hours_dir, _ = ensure_param_dirs(param)
    fn = iso_hour_filename(hour_start)
    path = hours_dir / fn
    subset = [r for r in records if r.get("parameter") == param]
    atomic_write_json(path, subset)
    logger.info(f"Wrote {param} hour {fn}: {len(subset)} rows")

# =========================
# MAIN
# =========================

def main():
    logger.info("=== stations_fetch start ===")

    for p in PARAMS: ensure_param_dirs(p)
    COMMON_DIR.mkdir(parents=True, exist_ok=True)

    features = refresh_sensors_geojson_if_needed()
    logger.info(f"Active features loaded: {len(features)}")

    # Non-US OpenAQ sensors per param (limited)
    non_us_ids = {p: [] for p in PARAMS}
    if not DISABLE_OPENAQ:
        for p in PARAMS:
            non_us_ids[p] = pick_openaq_sensor_ids(features, p, country_filter="non-US", limit=OPENAQ_MAX_SENSORS_PER_RUN)
        logger.info("OpenAQ non-US sensor sample per run: NO2=%d, O3=%d",
                    len(non_us_ids["no2"]), len(non_us_ids["o3"]))
    else:
        logger.info("OpenAQ disabled for this run (DISABLE_OPENAQ=true)")

    # Optional: US sensor sample (for backfill)
    us_ids = {p: [] for p in PARAMS}
    if OPENAQ_US_BACKFILL and not DISABLE_OPENAQ:
        for p in PARAMS:
            us_ids[p] = pick_openaq_sensor_ids(features, p, country_filter="US", limit=US_BACKFILL_MAX_SENSORS)
        logger.info("OpenAQ US backfill sample per run: NO2=%d, O3=%d",
                    len(us_ids["no2"]), len(us_ids["o3"]))

    # Target hours: H-2, H-1, H
    now_top = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    target_hours = [now_top - timedelta(hours=h) for h in [2, 1, 0]]

    for hour_start in target_hours:
        start_ts = time.time()
        ts = iso_hour(hour_start)
        logger.info(f"Processing hour {ts} …")

        # 1) AirNow → write immediately (ensures files exist even if OpenAQ is slow)
        airnow_records = fetch_airnow_hour(hour_start, BBOX_US, "OZONE,NO2")
        logger.info(f"AirNow {ts}: {len(airnow_records)} rows")
        for p in PARAMS:
            save_hour(p, hour_start, airnow_records)
            update_index(p)
            cleanup_old_hours(p)

        # 2) If time allows → OpenAQ non-US complement
        if not DISABLE_OPENAQ and (time.time() - start_ts) <= PER_HOUR_TIME_BUDGET:
            openaq_records_all: List[Dict[str, Any]] = []
            for p in PARAMS:
                sids = non_us_ids.get(p) or []
                if not sids: continue
                part = fetch_openaq_hours_for_sensors(sids, hour_start)
                openaq_records_all.extend(part)
                logger.info(f"OpenAQ(non-US) {ts} {p}: {len(part)} rows")
                if time.time() - start_ts > PER_HOUR_TIME_BUDGET:
                    logger.info(f"Time budget reached while fetching OpenAQ(non-US) for {ts}.")
                    break
            merged = dedup_merge_pref_airnow(airnow_records + openaq_records_all)
            for p in PARAMS:
                save_hour(p, hour_start, merged)
                update_index(p)
                cleanup_old_hours(p)

        # 3) Optional US backfill (only if AirNow looked thin for a param and time remains)
        if OPENAQ_US_BACKFILL and not DISABLE_OPENAQ and (time.time() - start_ts) <= PER_HOUR_TIME_BUDGET:
            # Quick check: if AirNow per-param count < threshold → try OpenAQ (US)
            # Reload just-written files to count AirNow per param for this hour
            for p in PARAMS:
                hours_dir, _ = ensure_param_dirs(p)
                fn = iso_hour_filename(hour_start)
                fpath = hours_dir / fn
                existing = load_json(fpath) or []
                airnow_count = sum(1 for r in existing if r.get("provider") == "AirNow")
                if airnow_count < US_BACKFILL_MIN_COUNT:
                    logger.info(f"US backfill {ts} {p}: AirNow count={airnow_count} < {US_BACKFILL_MIN_COUNT} → calling OpenAQ(US)")
                    sids_us = us_ids.get(p) or []
                    part_us = fetch_openaq_hours_for_sensors(sids_us, hour_start)
                    merged = dedup_merge_pref_airnow(existing + part_us)
                    save_hour(p, hour_start, merged)
                    update_index(p)
                    cleanup_old_hours(p)
                else:
                    logger.info(f"US backfill {ts} {p}: skipped (AirNow count={airnow_count} ok)")

    logger.info("=== stations_fetch done ===")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        ERR_LOG.exception(f"fatal: {e}")
        sys.exit(1)
