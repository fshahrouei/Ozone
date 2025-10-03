import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// A compact, card-styled Markdown references block for the About page.
/// Naming follows the style of `TeamMembersList` for consistency.
class ReferencesList extends StatelessWidget {
  const ReferencesList({super.key});

  static const String _markdown = '''
- **NASA TEMPO** — Tropospheric Emissions: Monitoring of Pollution  
  <https://tempo.si.edu/>

- **ECMWF ERA5** — Reanalysis (climate & meteorology)  
  <https://cds.climate.copernicus.eu/>

- **NOAA GFS (0.25°)** — Global Forecast System (u10, v10, BLH)  
  <https://www.ncei.noaa.gov/>

- **AirNow API** — U.S. air quality (NO₂, O₃)  
  <https://docs.airnowapi.org/>

- **OpenAQ** — Global air quality data platform  
  <https://openaq.org/>

- **Our World in Data (OWID)** — Greenhouse gas emissions  
  <https://ourworldindata.org/emissions>

- **EDGAR (JRC)** — Emissions Database for Global Atmospheric Research  
  <https://edgar.jrc.ec.europa.eu/>

- **UNFCCC** — National Inventory Submissions  
  <https://unfccc.int/>

- **OpenStreetMap (OSM)** — Base maps, boundaries  
  <https://www.openstreetmap.org/>

- **Open-Meteo** — Free weather forecasts API  
  <https://open-meteo.com/>

- **Flutter** — Cross-platform UI toolkit  
  <https://flutter.dev/>

- **Laravel** — Backend framework  
  <https://laravel.com/>

- **Python + NumPy, xarray, netCDF4, Requests** — Data processing & scientific pipelines  
  <https://www.python.org/>
''';

  Future<void> _onTapLink(
    String text,
    String? href,
    String title,
  ) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.parse(href);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        debugPrint('Could not launch $uri');
      }
    } catch (e) {
      debugPrint('Launch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: MarkdownBody(
        data: _markdown,
        selectable: true,
        onTapLink: _onTapLink,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: 14.5,
            height: 1.55,
            color: Colors.grey[800],
          ),
          a: const TextStyle(
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
            color: Colors.blue, // make links clearly blue
          ),
          listBullet: TextStyle(
            fontSize: 14.5,
            color: Colors.grey[700],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: card,
    );
  }
}
