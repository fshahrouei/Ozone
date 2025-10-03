# 📑 ClimateWise: An Integrated Framework for Air Quality, Climate, and Health Analytics

> **ClimateWise** is a three-layer system (Python ingestion → Laravel APIs → Flutter app with OSM basemaps) that turns raw scientific datasets into actionable insights for air quality, climate anomalies, greenhouse-gas emissions, and personalized health risk.

---
# 🌍 ClimateWise

**ClimateWise** is an open-source Android app that is **scientific, educational, and practical** for everyday users.  
It provides **air-pollution forecasts** for North America, along with **alerts, health tips, and heat maps** in a simple yet advanced interface.  

---

## 📥 Download
👉 [Get the latest APK](https://github.com/fshahrouei/ClimateWise/releases)  

---

## 🌐 Website
For more details, visit the [ClimateWise Support Website](https://climatewise.app)  

---

## ✨ Features
- Air-pollution forecasts (past, present, and upcoming hours)  
- Personalized health tips & notifications  
- Heat maps of pollutants and greenhouse gases  
- Simple, modern, and accessible design  

---

## ⚖️ License
This project is open-source under the [MIT License](./LICENSE).  

---

## Table of Contents

* [1. Introduction](#1-introduction)
* [2. System Architecture](#2-system-architecture)

  * [2.1 Overview](#21-overview)
  * [2.2 Data Flow](#22-data-flow)
  * [2.3 Technology Stack](#23-technology-stack)
  * [2.4 Scientific Transparency](#24-scientific-transparency)
* [3. AQMap: Air Quality Mapping Module](#3-aqmap-air-quality-mapping-module)

  * [3.1 Scientific Motivation](#31-scientific-motivation)
  * [3.2 Data Sources](#32-data-sources)
  * [3.3 Data Ingestion](#33-data-ingestion)
  * [3.4 API Layer](#34-api-layer)
  * [3.5 Algorithms](#35-algorithms)
  * [3.6 Visualization in Flutter](#36-visualization-in-flutter)
  * [3.7 Scientific Relevance](#37-scientific-relevance)
* [4. HeatMap: Climate Anomalies Module](#4-heatmap-climate-anomalies-module)

  * [4.1 Scientific Motivation](#41-scientific-motivation)
  * [4.2 Data Sources](#42-data-sources)
  * [4.3 Data Processing](#43-data-processing)
  * [4.4 API Layer](#44-api-layer)
  * [4.5 Visualization in Flutter](#45-visualization-in-flutter)
  * [4.6 Algorithms](#46-algorithms)
  * [4.7 Scientific Relevance](#47-scientific-relevance)
* [5. GHGMap: Greenhouse Gas Emissions Module](#5-ghgmap-greenhouse-gas-emissions-module)

  * [5.1 Scientific Motivation](#51-scientific-motivation)
  * [5.2 Data Sources](#52-data-sources)
  * [5.3 Data Processing Pipeline](#53-data-processing-pipeline)
  * [5.4 API Endpoints](#54-api-endpoints)
  * [5.5 Visualization in Flutter](#55-visualization-in-flutter)
  * [5.6 Algorithms and Metrics](#56-algorithms-and-metrics)
  * [5.7 Case Study: Country-Level Emissions](#57-case-study-country-level-emissions)
  * [5.8 Scientific Relevance](#58-scientific-relevance)
* [5. (Duplicate) GHGMap: Greenhouse Gas Emissions Module](#5-duplicate-ghgmap-greenhouse-gas-emissions-module)

  * [5.1 Scientific Motivation](#51-scientific-motivation-1)
  * [5.2 Data Sources](#52-data-sources-1)
  * [5.3 Data Processing Pipeline](#53-data-processing-pipeline-1)
  * [5.4 API Endpoints](#54-api-endpoints-1)
  * [5.5 Visualization in Flutter](#55-visualization-in-flutter-1)
  * [5.6 Algorithms and Metrics](#56-algorithms-and-metrics-1)
  * [5.7 Case Study: Country-Level Emissions](#57-case-study-country-level-emissions-1)
  * [5.8 Scientific Relevance](#58-scientific-relevance-1)
* [6. Health Advisor Module](#6-health-advisor-module)

  * [6.1 Conceptual Motivation](#61-conceptual-motivation)
  * [6.2 Data Inputs](#62-data-inputs)
  * [6.3 Backend Processing](#63-backend-processing)
  * [6.4 Frontend Visualization (Flutter)](#64-frontend-visualization-flutter)
  * [6.5 Scientific Underpinnings](#65-scientific-underpinnings)
  * [6.6 Integration with Other Modules](#66-integration-with-other-modules)
  * [6.7 Limitations](#67-limitations)
  * [6.8 Future Directions](#68-future-directions)
* [7. Cross-Module Integration and Automation](#7-cross-module-integration-and-automation)

  * [7.1 Integrated System View](#71-integrated-system-view)
  * [7.2 Automation via Cron Jobs](#72-automation-via-cron-jobs)
  * [7.3 Algorithmic Cohesion](#73-algorithmic-cohesion)
  * [7.4 Role of Flutter and OSM](#74-role-of-flutter-and-osm)
  * [7.5 Scientific and Societal Relevance](#75-scientific-and-societal-relevance)
* [8. Limitations and Future Work](#8-limitations-and-future-work)

  * [8.1 Current Limitations](#81-current-limitations)
  * [8.2 Planned Enhancements](#82-planned-enhancements)
* [9. Conclusion](#9-conclusion)
* [10. References (APA Style)](#10-references-apa-style)
* [11. Resources (Simple Links)](#11-resources-simple-links)

---

## 1. Introduction

The dual crises of **climate change** and **air pollution** have emerged as the defining environmental and public health challenges of the 21st century. Rising global temperatures, intensifying heatwaves, and escalating greenhouse gas (GHG) emissions are reshaping ecosystems and threatening human health. At the same time, short-lived climate pollutants—such as **nitrogen dioxide (NO₂)**, **ozone (O₃)**, and **formaldehyde (HCHO)**—pose acute risks to respiratory and cardiovascular systems, disproportionately affecting vulnerable populations including children, the elderly, and those with pre-existing conditions such as asthma or chronic obstructive pulmonary disease (COPD).

Scientific monitoring and public communication of these hazards remain fragmented. Agencies such as **NASA**, **ECMWF**, **NOAA**, and **World Bank** release vast datasets—ranging from satellite-based atmospheric chemistry (NASA TEMPO), reanalysis (ERA5), climate model ensembles (CMIP6), to socioeconomic inventories (Our World in Data, UNFCCC). However, these datasets are often difficult for policymakers, clinicians, and citizens to access, interpret, and apply in decision-making.

The **ClimateWise project** addresses this gap by providing an integrated platform that unites:

* **Air Quality Mapping (AQMap)** – High-resolution visualization of NO₂, HCHO, O₃, and cloud fraction, integrating satellite and ground-based stations.
* **HeatMap (Climate Anomalies)** – Historical and projected anomalies in surface air temperature, based on ERA5 reanalysis and CMIP6 model ensembles.
* **GHGMap (Greenhouse Gas Emissions)** – Country-level inventories of CO₂, CH₄, and N₂O, contextualized against global averages and historical trajectories.
* **Health Advisor** – Personalized health-risk scoring, translating pollutant exposure into disease-specific vulnerabilities.

Through a **three-layer architecture**—Python data ingestion pipelines, Laravel-based APIs, and a Flutter mobile client (with maps rendered via **OpenStreetMap** basemaps)—ClimateWise transforms raw scientific data into accessible, actionable insights.

The purpose of this document is to provide an **academic-style technical report** detailing the methods, algorithms, and data provenance of the ClimateWise system. It is intended for scholarly review by experts in environmental science, public health, and computational modeling.

---

## 2. System Architecture

### 2.1 Overview

The ClimateWise system employs a **modular architecture** designed to ensure scalability, reproducibility, and transparency. The pipeline can be conceptualized in four stages:

1. **Data Acquisition**

   * Python scripts (`tempo_to_json.py`, `stations_fetch.py`, `weather_fetch_run.py`) ingest raw datasets.
   * Sources include: NASA TEMPO, ERA5, CMIP6, AirNow, OpenAQ, NOAA GFS, Our World in Data.

2. **Preprocessing and Transformation**

   * NetCDF4 and CSV datasets are sanitized, normalized, and converted to JSON grids.
   * Procedures include **block reduction**, **cloud masking**, **outlier removal**, and **temporal alignment**.

3. **API Services (Laravel/PHP)**

   * Standardized REST endpoints under `/api/v1/frontend/*`.
   * Controllers:

     * `AirQualitiesController` (AQMap logic)
     * `HeatsController` (climate anomalies)
     * `OzonesController` (GHG emissions)
   * Each service handles queries such as `overlay-grids`, `legend`, `point-assess`, `countries`, `statistics`.

4. **Frontend Client (Flutter/Dart)**

   * Modules rendered as independent pages: AQMap, HeatMap, GHGMap, Health Advisor.
   * Interactive visualization with `flutter_map` and **OpenStreetMap** basemaps.
   * Offline-first architecture with caching and synchronization.
   * User-level data stored via SQLite/SharedPreferences; results optionally synchronized with server.

---

### 2.2 Data Flow

The **end-to-end data pipeline** is as follows:

* **Step 1: Acquisition**
  Cron jobs (every 30 minutes to 1 hour) trigger Python scripts to fetch the latest data from external APIs or OPeNDAP servers. For instance, TEMPO NetCDF files are harvested into `storage/app/tempo/`.

* **Step 2: Transformation**
  Data are normalized, downsampled, and stored as JSON arrays. Each pollutant has its own directory (`storage/app/tempo/no2/json`, `hcho/json`, etc.), with index files tracking metadata such as timestamps, bounding boxes, and grid dimensions.

* **Step 3: Serving via Laravel**
  API requests (e.g., `/api/v1/frontend/air-quality/overlays?product=no2`) return GeoJSON/PNG overlays or JSON data structures optimized for the Flutter frontend. Caching headers are carefully applied to balance freshness with efficiency.

* **Step 4: Visualization in Flutter**
  The client app requests overlays and point assessments from the API. Using `flutter_map` with OSM basemaps, pollutant fields are rendered as raster overlays, with legends mapped to perceptually uniform palettes (e.g., **Viridis colormap**). Health Advisor logic executes locally, combining pollutant levels with user profiles to generate personalized scores.

---

### 2.3 Technology Stack

* **Data Layer**:

  * Python 3.10
  * Libraries: `numpy`, `netCDF4`, `xarray`, `requests`
  * Tasks: NetCDF parsing, station ingest, weather alignment

* **Backend Layer**:

  * Laravel 10 (PHP 8)
  * Controllers and routes in `app/Http/Controllers/API/V1/Frontend/`
  * Endpoints for overlays, legends, forecasts, climate statistics

* **Frontend Layer**:

  * Flutter 3.x
  * Packages: `flutter_map`, `latlong2`, `provider`, `tutorial_coach_mark`
  * UI: modular tabs, responsive design, dark/light themes

* **Maps**:

  * Base: **OpenStreetMap** tiles (copyright compliant, attribution included)
  * Overlays: pollutant rasters, heat anomalies, GHG charts

---

### 2.4 Scientific Transparency

All components of ClimateWise emphasize **scientific reproducibility**:

* **Data provenance** explicitly documented (NASA, ECMWF, Our World in Data, AirNow, OpenAQ).
* **Algorithms** described with open-source code in Python and PHP.
* **APIs** publicly accessible and versioned (`/api/v1/frontend/*`).
* **Frontend** available as a cross-platform app with transparent legends and explanatory documentation.

---

## 3. AQMap: Air Quality Mapping Module

---

### 3.1 Scientific Motivation

The **Air Quality Map (AQMap)** represents the **core analytical engine** of ClimateWise. Its primary aim is to synthesize **satellite remote sensing data (NASA TEMPO)**, **ground-based observations (AirNow, OpenAQ)**, and **numerical weather reanalysis (ERA5, GFS)** into a coherent, user-accessible representation of near-real-time air pollution.

The pollutants selected—**NO₂**, **HCHO**, **O₃ total column (O₃tot)**, and **cloud fraction (CLDO4)**—are not arbitrary. Each pollutant offers distinct insights into atmospheric chemistry and human health impacts:

* **NO₂ (Nitrogen Dioxide):**

  * Short-lived pollutant, tracer of combustion, primarily from traffic and industry.
  * Acute respiratory irritant, linked to asthma exacerbations.
  * Precursor to ozone and secondary aerosols.

* **HCHO (Formaldehyde):**

  * Intermediate in volatile organic compound (VOC) oxidation.
  * Indicator of biogenic and anthropogenic emissions.
  * Proxy for surface ozone formation potential.

* **O₃tot (Total Column Ozone):**

  * Protective in the stratosphere, harmful at the surface.
  * Tropospheric O₃ contributes to photochemical smog.
  * Linked to cardiovascular mortality and crop yield losses.

* **CLDO4 (Cloud Fraction):**

  * Essential for interpreting satellite retrieval quality.
  * High cloud fractions obscure pollutant retrievals, requiring masking.

Together, these pollutants form the **diagnostic quartet** of atmospheric health in the troposphere.

---

### 3.2 Data Sources

AQMap integrates a range of **authoritative datasets**:

* **NASA TEMPO** (Tropospheric Emissions: Monitoring of Pollution)

  * Geostationary satellite mission launched in 2023.
  * Provides hourly NO₂, HCHO, and O₃ data over North America at ~10 km resolution.

* **AirNow (EPA/US):**

  * Real-time station network covering US & territories.
  * Provides NO₂ and O₃ hourly concentrations.

* **OpenAQ (Global):**

  * Aggregates official monitoring networks worldwide.
  * Complements AirNow outside North America.

* **NOAA GFS 0.25° Reanalysis:**

  * Meteorological fields: 10m wind (U, V), boundary layer height.
  * Used for pollutant transport modeling and interpolation.

* **ERA5 Reanalysis (ECMWF):**

  * Historical baseline and validation.

---

### 3.3 Data Ingestion

#### 3.3.1 TEMPO NetCDF Conversion

The script `tempo_to_json.py` handles ingestion of TEMPO Level-3 NetCDF granules:

* **Normalization:**
  Longitude wrapped to [-180,180), latitude aligned northward.

* **Grid Reduction:**
  Original fine grid downsampled to 0.1° via block averaging.

* **Cloud Masking:**
  Co-located CLDO4 product reindexed to pollutant grid. Values masked where CLDO4 > 0.3.

* **Sanitization:**

  * Negative or extreme outliers removed.
  * Values outside plausible bounds (e.g., NO₂ > 5×10¹⁶ molec/cm²) replaced with `NaN`.
  * `NaN` → `None` in JSON for validity.

* **Output JSON:**
  Each file contains:

  ```json
  {
    "product": "no2",
    "bbox": [S, N, W, E],
    "shape": [H, W],
    "unit": "molec/cm²",
    "lat": [...],
    "lon": [...],
    "data": [[...]]
  }
  ```

#### 3.3.2 Stations Fetch

The script `stations_fetch.py`:

* Prioritizes **AirNow** data (higher reliability in the US).
* Falls back to **OpenAQ** for global or sparse regions.
* Applies **deduplication** with preference for AirNow.
* Normalizes units (PPM → PPB).
* Writes hourly JSON files in `storage/app/stations/`.

---

### 3.4 API Layer

The Laravel controller `AirQualitiesController` exposes AQMap endpoints:

* `/overlays` → Raster overlays for pollutant fields.
* `/overlay-times` → Available frames for animation.
* `/overlay-grids` → High-resolution JSON grid data (zoom > 8).
* `/legend` → Color palette, ticks, units.
* `/forecast-grids` → 12-hour forecasts, aligned to TEMPO grid.
* `/point-assess` → Point-level health risk assessment.
* `/stations` → Near-real-time ground station data.

Caching strategy ensures low latency while preserving hourly freshness.

---

### 3.5 Algorithms

#### 3.5.1 Raster Overlay Generation

Overlays are generated via:

1. Fetch pollutant grid (`no2`, `hcho`, `o3tot`, or `cldo4`).
2. Apply color mapping (Viridis for pollutants, Grayscale for clouds).
3. Render raster to PNG tile overlay.
4. Serve via `/overlays?product=no2&z=5`.

#### 3.5.2 Point Assessment

The **`PointAssess`** service computes exposure risk for a given lat/lon:

* **Inputs:**

  * Pollutant weights per disease (e.g., Asthma risk weighted 50% by NO₂).
  * User sensitivity factor (0..1).

* **Algorithm:**
  [
  \text{score}*{\text{disease}} = \sum*{p \in {no2, hcho, o3tot}} w_{p,\text{disease}} \cdot \frac{C_p}{C_{p,\text{cap}}}
  ]

* **Outputs:**

  * Individual disease risk scores.
  * Aggregated overall health risk (normalized 0–100).

---

### 3.6 Visualization in Flutter

* **Basemap:** OSM tiles (`© OpenStreetMap contributors`).
* **Overlays:** pollutant rasters (PNG or JSON).
* **Legends:** dynamic, based on product palette and units.
* **User Interactions:**

  * Tap → fetch `PointAssess` from backend.
  * Animated timeline of overlays.
  * Station markers with tooltip popups.

**Example (pseudo-code in Flutter):**

```dart
FlutterMap(
  options: MapOptions(center: LatLng(40.7, -73.9), zoom: 5),
  children: [
    TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"),
    ImageOverlay(imageProvider: NetworkImage(apiOverlayUrl)),
    LegendWidget(legendData),
  ],
);
```

---

### 3.7 Scientific Relevance

AQMap provides a **spatiotemporal bridge** between satellite atmospheric chemistry and local public health. By translating abstract units (e.g., DU, molec/cm²) into color-coded maps and risk scores, it empowers users—including policymakers, educators, and citizens—to grasp the invisible dynamics of air pollution.

---

## 4. HeatMap: Climate Anomalies Module

---

### 4.1 Scientific Motivation

While AQMap provides near-real-time atmospheric pollution fields, the **HeatMap module** addresses the **long-term signal of climate change**. It visualizes both **historical anomalies** (past deviations in surface air temperature from a baseline climatology) and **projected anomalies** (future warming scenarios).

Understanding heat anomalies is critical because:

* **Human health impacts**: Extreme heat events increase mortality from heatstroke, cardiovascular stress, and respiratory disease.
* **Ecosystem impacts**: Altered species distributions, coral bleaching, and wildfire risk are linked to warming.
* **Economic consequences**: Reduced labor productivity, crop yield losses, and increased energy demand.

Thus, HeatMap situates daily air-quality risks within the broader trajectory of **global warming**.

---

### 4.2 Data Sources

HeatMap relies on a **multi-tier data ecosystem**:

* **ERA5 Reanalysis (ECMWF Copernicus Climate Data Store):**

  * Gridded dataset of historical climate (1950–present).
  * Surface air temperature (2m).
  * Resolution: 0.25°.

* **CMIP6 Model Ensemble (IPCC AR6):**

  * Scenarios SSP1–2.6, SSP2–4.5, SSP5–8.5.
  * Projections for 21st century warming.
  * Used to contextualize observed trends.

* **Our World in Data (OWID):**

  * Pre-processed country-level temperature anomaly datasets.
  * Derived from Berkeley Earth and NASA GISTEMP.

---

### 4.3 Data Processing

The HeatMap module’s preprocessing pipeline:

1. **Baseline Climatology**

   * Mean temperature 1951–1980 (NASA GISTEMP standard).

2. **Anomaly Computation**

   * For each year:
     [
     \Delta T(y) = T(y) - T_{\text{baseline}}
     ]
   * Expressed in °C.

3. **Country-Level Aggregation**

   * ERA5 grid points are spatially averaged over administrative boundaries.
   * OWID country datasets provide ready-to-use aggregates.

4. **Future Projections**

   * CMIP6 models averaged for each SSP scenario.
   * Bias correction applied by aligning model baseline with ERA5.

---

### 4.4 API Layer

Laravel backend exposes HeatMap endpoints:

* `/api/v1/frontend/heat-map/countries`
  Returns anomaly timeseries per country.

* `/api/v1/frontend/heat-map/global`
  Returns global mean anomalies.

* `/api/v1/frontend/heat-map/scenarios`
  Provides CMIP6 scenario data.

* `/api/v1/frontend/heat-map/legend`
  Defines color palette (blue = cooler, red = hotter).

---

### 4.5 Visualization in Flutter

The Flutter HeatMap page presents:

* **Global Map (choropleth):**

  * Countries shaded by anomaly in selected year.
  * Blue–red diverging color scale.

* **Timeline Slider:**

  * User can animate anomalies from 1950 → 2100.

* **Country Detail Panel:**

  * Line chart of anomalies across time.
  * Overlay of SSP scenarios for future trajectories.

**Example (pseudo-code):**

```dart
LineChart(
  LineChartData(
    lineBarsData: [
      LineChartBarData(spots: countryHistoricalAnomalies),
      LineChartBarData(spots: ssp245Projection, isCurved: true),
      LineChartBarData(spots: ssp585Projection, isCurved: true),
    ],
  ),
);
```

---

### 4.6 Algorithms

* **Normalization:** Ensure anomalies are relative to baseline (1951–1980).
* **Interpolation:** Fill missing years via linear interpolation.
* **Scenario Alignment:** Shift CMIP6 model outputs so that historical overlap (1951–2010) matches ERA5/observations.
* **Smoothing:** Optional LOESS smoothing to reduce interannual noise.

---

### 4.7 Scientific Relevance

The HeatMap module bridges **climate science and public communication**. It enables users to see:

* Their country’s deviation from the pre-industrial baseline.
* The stark contrast between mitigation (SSP1–2.6) and high-emission pathways (SSP5–8.5).
* The implications of exceeding **+1.5°C** and **+2°C** thresholds defined by the Paris Agreement.

This visualization demystifies abstract climate reports by grounding them in **intuitive, interactive maps and charts**.

---

## 5. GHGMap: Greenhouse Gas Emissions Module

---

### 5.1 Scientific Motivation

While AQMap and HeatMap focus on atmospheric concentrations and anomalies, the **GHGMap module** addresses the **root drivers** of climate change: the emission of greenhouse gases (GHGs). By quantifying emissions at the national and regional level, it allows users to link human activity with downstream atmospheric effects and climate outcomes.

Key questions addressed by GHGMap include:

* Which countries are the largest contributors to cumulative GHG emissions?
* How do emissions of different gases (CO₂, CH₄, N₂O) compare?
* How have emissions evolved historically, and what pathways are possible for the future?
* What is the relative role of developed vs. developing regions in global totals?

This module transforms emissions inventories into intuitive, interactive maps and charts that highlight the **cause-and-effect chain** from human activity → atmospheric chemistry → climate impacts.

---

### 5.2 Data Sources

The GHGMap module relies on **authoritative international datasets**:

* **Our World in Data (OWID):**

  * Greenhouse gas emissions by gas, sector, and country.
  * Derived from Global Carbon Project, EDGAR (Emissions Database for Global Atmospheric Research), and UNFCCC submissions.
  * CSV downloads from OWID serve as the primary backend input.

* **EDGAR (European Commission Joint Research Centre):**

  * Detailed emissions by sector (energy, industry, transport, agriculture, waste).
  * Resolution: national + grid.

* **UNFCCC National Inventory Submissions:**

  * Official reports by Parties to the UNFCCC.
  * Used for verification of OWID data.

* **FAOSTAT (Food and Agriculture Organization):**

  * Agricultural CH₄ and N₂O emissions.

---

### 5.3 Data Processing Pipeline

The Laravel backend (PHP) processes raw CSV files (`ghg.csv`) into country-level and year-level summaries.

**Steps:**

1. **Parsing CSV**

   * Columns: `Entity, ISO_A3, Year, N₂O, CH₄, CO₂`.

2. **Total Emissions Computation**

   * Sum across gases:
     [
     E_{\text{total}}(c,y) = E_{CO₂}(c,y) + E_{CH₄}(c,y) + E_{N₂O}(c,y)
     ]

3. **Score Assignment**

   * A normalized “emission intensity score” (1–10) is computed:

     * ≥ 10 billion tonnes = 10
     * ≥ 3 billion tonnes = 9
     * … down to < 1 million tonnes = 1
   * Used for choropleth shading.

4. **Filtering**

   * Non-country aggregates (e.g., `WORLD`, `ASIA`, `EUROPE`) excluded.

5. **Flag Enrichment**

   * ISO3 → ISO2 conversion (via mapping table).
   * Associated with public flag assets (SVG/PNG).

6. **Top 10 Ranking**

   * Countries ranked by emissions in a given year.
   * Top 10 + “Others” aggregate.

7. **History Extraction**

   * For each country, last 25 years retained as history for line charts.

---

### 5.4 API Endpoints

Laravel provides the following GHGMap endpoints:

* `/api/v1/frontend/ozones/countries/{year}`
  Returns emissions by country for a given year.

* `/api/v1/frontend/ozones/country/{iso_a3}/{year}`
  Returns detailed emissions for a country, including history and ranking.

* `/api/v1/frontend/ozones/years`
  Returns the list of available years (1850–2023).

* `/api/v1/frontend/ozones/statistics/{year}`
  Returns top 10 emitters, others aggregate, and global total for the selected year.

* `/api/v1/frontend/ozones/generateGeoJson`
  Generates simplified GeoJSON for visualization (countries with properties).

---

### 5.5 Visualization in Flutter

The Flutter GHGMap page displays emissions data with multiple layers:

* **Choropleth World Map:**

  * Countries shaded by emission score.
  * Colors range from light yellow (low emitters) → deep red (high emitters).

* **Time Slider:**

  * Allows users to animate changes in emissions from 1850 → 2023.

* **Country Detail Panel:**

  * Shows:

    * Current year emissions by gas (bar chart).
    * 25-year history (line chart).
    * Share of global emissions (%).
    * Position in global ranking.

**Example Flutter pseudocode:**

```dart
BarChart(
  BarChartData(
    titlesData: FlTitlesData(show: true),
    barGroups: [
      BarChartGroupData(x: 0, barRods: [BarChartRodData(y: countryData.co2)]),
      BarChartGroupData(x: 1, barRods: [BarChartRodData(y: countryData.ch4)]),
      BarChartGroupData(x: 2, barRods: [BarChartRodData(y: countryData.n2o)]),
    ],
  ),
);
```

---

### 5.6 Algorithms and Metrics

* **Per-capita emissions:**
  [
  E_{pc}(c,y) = \frac{E_{total}(c,y)}{Population(c,y)}
  ]
  OWID provides population data to normalize emissions.

* **Cumulative emissions:**
  [
  E_{cum}(c) = \sum_{y=1850}^{2023} E_{total}(c,y)
  ]
  Useful for assessing historical responsibility.

* **Ranking Stability:**
  A Kendall rank correlation is computed across decades to see which countries consistently remain top emitters.

* **Others Aggregation:**
  [
  E_{\text{others}}(y) = E_{\text{global}}(y) - \sum_{i=1}^{10} E_{top_i}(y)
  ]

---

### 5.7 Case Study: Country-Level Emissions

**Example: United States (USA)**

* Peak emissions in 2005 (~7 Gt CO₂e).
* Decline thereafter due to natural gas replacing coal, efficiency gains, and renewables.
* Still among the largest emitters.

**Example: China (CHN)**

* Rapid growth post-2000 due to industrial expansion.
* Surpassed USA as largest emitter ~2006.
* Accounts for ~30% of global total in 2023.

---

### 5.8 Scientific Relevance

GHGMap situates countries in the **global carbon accountability debate**. It highlights:

* **Equity vs. responsibility:** Developed countries’ historical emissions vs. developing countries’ current growth.
* **Paris Agreement goals:** Nationally Determined Contributions (NDCs) require drastic reductions.
* **Transparency:** Public access to comparable emissions data strengthens accountability.

By presenting these data in an accessible, interactive manner, ClimateWise empowers citizens, researchers, and policymakers alike.

---

## 5. (Duplicate) GHGMap: Greenhouse Gas Emissions Module

> *(Content repeated intentionally and preserved verbatim as provided.)*

### 5.1 Scientific Motivation

While AQMap and HeatMap focus on atmospheric concentrations and anomalies, the **GHGMap module** addresses the **root drivers** of climate change: the emission of greenhouse gases (GHGs). By quantifying emissions at the national and regional level, it allows users to link human activity with downstream atmospheric effects and climate outcomes.

Key questions addressed by GHGMap include:

* Which countries are the largest contributors to cumulative GHG emissions?
* How do emissions of different gases (CO₂, CH₄, N₂O) compare?
* How have emissions evolved historically, and what pathways are possible for the future?
* What is the relative role of developed vs. developing regions in global totals?

This module transforms emissions inventories into intuitive, interactive maps and charts that highlight the **cause-and-effect chain** from human activity → atmospheric chemistry → climate impacts.

---

### 5.2 Data Sources

The GHGMap module relies on **authoritative international datasets**:

* **Our World in Data (OWID):**

  * Greenhouse gas emissions by gas, sector, and country.
  * Derived from Global Carbon Project, EDGAR (Emissions Database for Global Atmospheric Research), and UNFCCC submissions.
  * CSV downloads from OWID serve as the primary backend input.

* **EDGAR (European Commission Joint Research Centre):**

  * Detailed emissions by sector (energy, industry, transport, agriculture, waste).
  * Resolution: national + grid.

* **UNFCCC National Inventory Submissions:**

  * Official reports by Parties to the UNFCCC.
  * Used for verification of OWID data.

* **FAOSTAT (Food and Agriculture Organization):**

  * Agricultural CH₄ and N₂O emissions.

---

### 5.3 Data Processing Pipeline

The Laravel backend (PHP) processes raw CSV files (`ghg.csv`) into country-level and year-level summaries.

**Steps:**

1. **Parsing CSV**

   * Columns: `Entity, ISO_A3, Year, N₂O, CH₄, CO₂`.

2. **Total Emissions Computation**

   * Sum across gases:
     [
     E_{\text{total}}(c,y) = E_{CO₂}(c,y) + E_{CH₄}(c,y) + E_{N₂O}(c,y)
     ]

3. **Score Assignment**

   * A normalized “emission intensity score” (1–10) is computed:

     * ≥ 10 billion tonnes = 10
     * ≥ 3 billion tonnes = 9
     * … down to < 1 million tonnes = 1
   * Used for choropleth shading.

4. **Filtering**

   * Non-country aggregates (e.g., `WORLD`, `ASIA`, `EUROPE`) excluded.

5. **Flag Enrichment**

   * ISO3 → ISO2 conversion (via mapping table).
   * Associated with public flag assets (SVG/PNG).

6. **Top 10 Ranking**

   * Countries ranked by emissions in a given year.
   * Top 10 + “Others” aggregate.

7. **History Extraction**

   * For each country, last 25 years retained as history for line charts.

---

### 5.4 API Endpoints

Laravel provides the following GHGMap endpoints:

* `/api/v1/frontend/ozones/countries/{year}`
  Returns emissions by country for a given year.

* `/api/v1/frontend/ozones/country/{iso_a3}/{year}`
  Returns detailed emissions for a country, including history and ranking.

* `/api/v1/frontend/ozones/years`
  Returns the list of available years (1850–2023).

* `/api/v1/frontend/ozones/statistics/{year}`
  Returns top 10 emitters, others aggregate, and global total for the selected year.

* `/api/v1/frontend/ozones/generateGeoJson`
  Generates simplified GeoJSON for visualization (countries with properties).

---

### 5.5 Visualization in Flutter

The Flutter GHGMap page displays emissions data with multiple layers:

* **Choropleth World Map:**

  * Countries shaded by emission score.
  * Colors range from light yellow (low emitters) → deep red (high emitters).

* **Time Slider:**

  * Allows users to animate changes in emissions from 1850 → 2023.

* **Country Detail Panel:**

  * Shows:

    * Current year emissions by gas (bar chart).
    * 25-year history (line chart).
    * Share of global emissions (%).
    * Position in global ranking.

**Example Flutter pseudocode:**

```dart
BarChart(
  BarChartData(
    titlesData: FlTitlesData(show: true),
    barGroups: [
      BarChartGroupData(x: 0, barRods: [BarChartRodData(y: countryData.co2)]),
      BarChartGroupData(x: 1, barRods: [BarChartRodData(y: countryData.ch4)]),
      BarChartGroupData(x: 2, barRods: [BarChartRodData(y: countryData.n2o)]),
    ],
  ),
);
```

---

### 5.6 Algorithms and Metrics

* **Per-capita emissions:**
  [
  E_{pc}(c,y) = \frac{E_{total}(c,y)}{Population(c,y)}
  ]
  OWID provides population data to normalize emissions.

* **Cumulative emissions:**
  [
  E_{cum}(c) = \sum_{y=1850}^{2023} E_{total}(c,y)
  ]
  Useful for assessing historical responsibility.

* **Ranking Stability:**
  A Kendall rank correlation is computed across decades to see which countries consistently remain top emitters.

* **Others Aggregation:**
  [
  E_{\text{others}}(y) = E_{\text{global}}(y) - \sum_{i=1}^{10} E_{top_i}(y)
  ]

---

### 5.7 Case Study: Country-Level Emissions

**Example: United States (USA)**

* Peak emissions in 2005 (~7 Gt CO₂e).
* Decline thereafter due to natural gas replacing coal, efficiency gains, and renewables.
* Still among the largest emitters.

**Example: China (CHN)**

* Rapid growth post-2000 due to industrial expansion.
* Surpassed USA as largest emitter ~2006.
* Accounts for ~30% of global total in 2023.

---

### 5.8 Scientific Relevance

GHGMap situates countries in the **global carbon accountability debate**. It highlights:

* **Equity vs. responsibility:** Developed countries’ historical emissions vs. developing countries’ current growth.
* **Paris Agreement goals:** Nationally Determined Contributions (NDCs) require drastic reductions.
* **Transparency:** Public access to comparable emissions data strengthens accountability.

By presenting these data in an accessible, interactive manner, ClimateWise empowers citizens, researchers, and policymakers alike.

---

## 6. Health Advisor Module

---

### 6.1 Conceptual Motivation

While AQMap, HeatMap, and GHGMap address atmospheric phenomena and emissions, the **Health Advisor module** directly connects air quality with **human health impacts**. This makes it the most user-centric module in ClimateWise, as it translates complex pollutant concentrations into **actionable guidance for individuals and vulnerable groups**.

The core idea:

* Gather user-specific information (location, age, sensitivity to diseases).
* Combine with current and forecasted pollutant data.
* Apply medical heuristics and risk-weight algorithms.
* Produce **personalized health scores and alerts**.

This approach is aligned with recommendations from **WHO (World Health Organization)** and **EPA (United States Environmental Protection Agency)** guidelines on air pollution and health.

---

### 6.2 Data Inputs

Health Advisor integrates multiple streams:

1. **Air quality products** (from AQMap):

   * Pollutants: NO₂, HCHO, O₃, Cloud fraction (CLDO4 as data quality mask).
   * Spatial resolution: ~0.1°.
   * Temporal resolution: hourly forecast window (up to +72h).

2. **Weather variables** (from weather_fetch_run.py):

   * Wind speed/direction, boundary layer height (BLH).
   * Affect pollutant dispersion.

3. **User profile data:**

   * Name (optional).
   * Sensitivity group (e.g., asthma, cardiovascular disease).
   * Geolocation (picked from map).

4. **Medical risk factors:**

   * Risk weight tables for diseases, based on pollutant exposure-response functions.
   * Example: Asthma weighted strongly to NO₂; cardiovascular disease weighted to O₃.

---

### 6.3 Backend Processing

The Laravel server (HealthAdvisorController + PointAssess class) executes the aggregation logic:

1. **Pollutant Normalization**
   Pollutant concentrations are normalized into a 0–1 scale based on WHO guideline values and historical distributions.
   Example for NO₂:
   [
   N_{\text{NO₂}} = \frac{\min(C_{\text{NO₂}}, C_{\text{max}})}{C_{\text{WHO_limit}}}
   ]
   where ( C_{\text{max}} ) is capped at 200 µg/m³, and WHO annual limit is 40 µg/m³.

2. **Weighted Risk Score**
   Each disease has a weight vector across pollutants.
   Example:

   * Asthma: {NO₂: 0.50, HCHO: 0.35, O₃: 0.15, CLDO4: 0.00}.
   * Cardiovascular: {O₃: 0.60, NO₂: 0.30, HCHO: 0.10}.
     Risk score:
     [
     S_{\text{disease}} = \sum_{p \in {\text{NO₂},\text{HCHO},\text{O₃}}} w_{p} \cdot N_{p}
     ]

3. **Overall Health Index**
   Combine across selected diseases:
   [
   H_{\text{overall}} = \frac{1}{|D|} \sum_{d \in D} S_{\text{disease}}
   ]
   Scaled to 0–100 for user interpretation.

4. **Alert Generation**
   If ( H_{\text{overall}} > 70 ), generate health alerts (e.g., “Avoid outdoor activity”).

---

### 6.4 Frontend Visualization (Flutter)

The Flutter Health Advisor UI integrates multiple components:

* **Tabs:**

  * *Form*: User enters sensitivity and location.
  * *Saved*: Previous assessments stored locally and via API.

* **Gauge Chart:**

  * Shows current health index (0–100).
  * Colors: green (safe), yellow (moderate), red (hazardous).

* **Risk Breakdown:**

  * Bar chart per disease.
  * Highlights pollutants most responsible for risk.

* **Coach Marks (tutorial):**

  * Guides new users step by step through tabs, maps, gauges, and alerts.

---

### 6.5 Scientific Underpinnings

Health Advisor is inspired by several frameworks:

* **WHO Air Quality Guidelines (2021 update):** threshold values for PM₂.₅, NO₂, O₃.
* **EPA AQI (Air Quality Index):** mapping pollutant concentration ranges to categories.
* **Epidemiological studies** (e.g., Jerrett et al., 2009; Burnett et al., 2018) linking chronic exposure to asthma, COPD, cardiovascular diseases.
* **Risk aggregation models** in environmental health (weighted-sum methods widely used in Multi-Criteria Decision Analysis).

This ensures that while the Health Advisor is simplified for public use, it remains grounded in **peer-reviewed science**.

---

### 6.6 Integration with Other Modules

* Pulls **real-time pollutants** from AQMap.
* Uses **weather dispersion factors** (BLH, winds) from Weather module.
* Allows comparison with **GHGMap** trends (macro vs. micro perspective).

---

### 6.7 Limitations

* Not a substitute for medical advice; results are heuristic.
* Limited pollutant set (NO₂, HCHO, O₃ only; no PM₂.₅ yet).
* User-entered sensitivity may be subjective.
* Does not yet model **lagged effects** (e.g., multi-day ozone exposure).

---

### 6.8 Future Directions

* Integration of **PM₂.₅** from satellite (e.g., MODIS, VIIRS AOD → PM₂.₅ conversion).
* Dynamic personalization (age, occupation, mobility).
* Integration with **wearables** (heart rate, breathing rate) for adaptive recommendations.
* Machine learning models for non-linear exposure-response.

---

## 7. Cross-Module Integration and Automation

---

### 7.1 Integrated System View

The four modules—**AQMap, HeatMap, GHGMap, and Health Advisor**—are not isolated components but interconnected parts of a unified climate-health intelligence platform.

* **AQMap** supplies fine-scale atmospheric concentrations (NO₂, HCHO, O₃, CLDO4).
* **HeatMap** contextualizes anomalies and long-term deviations in temperature or other climate indicators.
* **GHGMap** situates countries in the global emissions context, linking human activity to atmospheric changes.
* **Health Advisor** translates pollutant data into health guidance.

Together, they form a **data pipeline**:

**Raw Satellite/Station Data → Python Preprocessing → Laravel APIs → Flutter Frontend → User Insights.**

---

### 7.2 Automation via Cron Jobs

Reliable delivery requires strict automation. Cron jobs ensure continuous ingestion, transformation, and serving of data.

**Examples (production setup):**

1. **TEMPO Preprocessing (every 30 minutes):**

   ```bash
   cd /home/fariba_shahrooee/climatewise.app && \
   ./.venv/bin/python py/tempo_to_json.py --product=no2 --grid=0.1 --cloud-th=0.3 --keep-hours=72
   ```

2. **Forecast Summaries (aligned with above):**

   ```bash
   ./.venv/bin/python py/build_tempo_forecast_summaries.py --product no2 --hours 72
   ```

3. **Weather Data (hourly):**

   ```bash
   ./.venv/bin/python py/weather_fetch_run.py
   ```

4. **Stations Data (AirNow + OpenAQ, hourly):**

   ```bash
   ./.venv/bin/python py/stations_fetch.py
   ```

5. **Cleanup Jobs:**

   * Remove outdated weather runs, station files, and tiles beyond 72h.
   * Example:

     ```bash
     ./scripts/cleanup_tiles.sh --keep-hours 72
     ```

This pipeline guarantees:

* **Freshness:** AQ data updated every 30 minutes.
* **Reliability:** Redundancy between AirNow and OpenAQ.
* **Efficiency:** Disk cleanup avoids overload.

---

### 7.3 Algorithmic Cohesion

The modules interlock through consistent methods:

* **Gridding:** All spatial datasets re-projected to a ~0.1° grid.
* **Normalization:** Pollutant concentrations scaled against WHO/EPA guidelines.
* **Temporal harmonization:** 72-hour rolling window with hourly resolution.
* **Scoring functions:**

  * AQMap: concentration → AQI-like index.
  * HeatMap: anomaly relative to climatology.
  * GHGMap: emissions → normalized score (1–10).
  * Health Advisor: weighted pollutant indices → health risk score.

---

### 7.4 Role of Flutter and OSM

* **Flutter:** Provides cross-platform mobile delivery.

  * Uses `flutter_map` for geospatial rendering.
  * Charts with `fl_chart` (gauges, bars, lines).
  * State management via `provider`.

* **OpenStreetMap (OSM):** Base maps and country boundaries.

  * GeoJSON boundaries from OSM (via external simplification tools).
  * Attribution shown on maps (“© OpenStreetMap contributors”).

---

### 7.5 Scientific and Societal Relevance

The ClimateWise system is positioned as both:

* **A scientific demonstrator:**

  * Validating NASA TEMPO data.
  * Demonstrating multi-source integration (satellites + ground + inventories).

* **A societal tool:**

  * Educating public on causes (GHGMap), symptoms (AQMap), deviations (HeatMap), and personal impacts (Health Advisor).
  * Aligning with UN Sustainable Development Goals (SDG 3: Health, SDG 13: Climate Action).

---

## 8. Limitations and Future Work

### 8.1 Current Limitations

* **Pollutant scope:** No PM₂.₅/PM₁₀ yet (due to satellite data constraints).
* **Geographic bias:** AQ stations dense in US/Europe, sparse in Africa/Asia.
* **Model simplifications:** Linear risk weights; no non-linear dose-response curves.
* **Uncertainty handling:** Limited propagation of satellite retrieval errors.

### 8.2 Planned Enhancements

* Add **PM₂.₅** using MODIS/VIIRS AOD conversion algorithms.
* Introduce **machine learning models** for exposure-response.
* Expand to **multi-language interfaces** (EN/FA/AR).
* Publish **open APIs** for third-party integration.
* Extend beyond 72h forecast via **coupled chemistry-climate models** (e.g., WRF-Chem).

---

## 9. Conclusion

ClimateWise demonstrates how a **modern software architecture (Python + Laravel + Flutter)** can operationalize cutting-edge scientific datasets into a **public health and climate awareness tool**.

By integrating:

* **NASA TEMPO** (atmospheric trace gases),
* **ERA5/GFS** (weather reanalyses),
* **AirNow/OpenAQ** (ground stations),
* **OWID/EDGAR/UNFCCC** (emissions inventories),
* **OpenStreetMap** (geospatial context),

…the system bridges science and society.

Its modular design ensures scalability: new pollutants, diseases, or datasets can be integrated with minimal redesign. The combination of automation (cron jobs), rigorous data handling (NaN-safe JSON, normalized indices), and user-friendly delivery (Flutter mobile maps, charts) makes ClimateWise a unique contribution at the intersection of **climate science, data engineering, and digital health**.

---

## 10. References (APA Style)

* Burnett, R., et al. (2018). *Global estimates of mortality associated with long-term exposure to outdoor fine particulate matter*. PNAS.
* Jerrett, M., et al. (2009). *Long-term ozone exposure and mortality*. NEJM.
* NASA. (2023). *TEMPO: Tropospheric Emissions: Monitoring of Pollution*. [https://tempo.si.edu](https://tempo.si.edu)
* NOAA. (2023). *Global Forecast System (GFS) 0.25°*. [https://www.ncei.noaa.gov](https://www.ncei.noaa.gov)
* WHO. (2021). *Air quality guidelines: Global update 2021*. World Health Organization.
* Our World in Data. (2023). *Greenhouse Gas Emissions*. [https://ourworldindata.org/emissions](https://ourworldindata.org/emissions)
* EDGAR. (2023). *Emissions Database for Global Atmospheric Research*. European Commission JRC.
* UNFCCC. (2023). *National Inventory Submissions*. [https://unfccc.int](https://unfccc.int)
* OpenAQ. (2023). *Air Quality Data Platform*. [https://openaq.org](https://openaq.org)
* AirNow. (2023). *AirNow API*. [https://docs.airnowapi.org](https://docs.airnowapi.org)
* ECMWF. (2023). *ERA5 Reanalysis*. [https://cds.climate.copernicus.eu](https://cds.climate.copernicus.eu)
* OpenStreetMap. (2023). *Planet OSM Data*. [https://www.openstreetmap.org](https://www.openstreetmap.org)
* Flutter. (2023). *Flutter SDK Documentation*. [https://flutter.dev](https://flutter.dev)
* Laravel. (2023). *Laravel Framework Documentation*. [https://laravel.com](https://laravel.com)

---

## 11. Resources (Simple Links)

* NASA TEMPO → [https://tempo.si.edu](https://tempo.si.edu)
* ERA5 (ECMWF) → [https://cds.climate.copernicus.eu](https://cds.climate.copernicus.eu)
* NOAA GFS → [https://www.ncei.noaa.gov](https://www.ncei.noaa.gov)
* AirNow API → [https://docs.airnowapi.org](https://docs.airnowapi.org)
* OpenAQ API → [https://openaq.org](https://openaq.org)
* Our World in Data (OWID) → [https://ourworldindata.org/emissions](https://ourworldindata.org/emissions)
* EDGAR → [https://edgar.jrc.ec.europa.eu](https://edgar.jrc.ec.europa.eu)
* UNFCCC → [https://unfccc.int](https://unfccc.int)
* FAOSTAT → [https://www.fao.org/faostat](https://www.fao.org/faostat)
* OpenStreetMap → [https://www.openstreetmap.org](https://www.openstreetmap.org)
* Flutter SDK → [https://flutter.dev](https://flutter.dev)
* Laravel Framework → [https://laravel.com](https://laravel.com)
