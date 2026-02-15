"""
dashboard.py — Generate a travel story dashboard with trip stamps and timeline.

Receives a timeline dict (from trips.py) and renders:
- Trip stamps (Airbnb-style, clickable/expandable)
- Scrollable horizontal timeline
- Trip map
All assembled into a single HTML file via Jinja2.
"""

import json
import os
from datetime import datetime, date

import plotly.graph_objects as go
import plotly.express as px
from jinja2 import Environment, FileSystemLoader

# Color palette for years
YEAR_COLORS = px.colors.qualitative.Set2

# Country → emoji flag (common ones; fallback handled in template)
COUNTRY_FLAGS = {
    "Türkiye": "TR", "United States": "US", "United Kingdom": "GB",
    "Netherlands": "NL", "Greece": "GR", "Italy": "IT", "France": "FR",
    "Germany": "DE", "Belgium": "BE", "Luxembourg": "LU", "Singapore": "SG",
    "Serbia": "RS", "Cyprus": "CY", "Malta": "MT", "Romania": "RO",
    "Switzerland": "CH", "Liechtenstein": "LI", "Ireland": "IE",
    "Albania": "AL", "San Marino": "SM", "Croatia": "HR",
}


def _cc_to_flag(cc):
    """Convert a 2-letter country code to a flag emoji (e.g. 'TR' → '🇹🇷')."""
    if not cc or len(cc) != 2:
        return ""
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in cc.upper())


def _build_trip_map(timeline):
    """Interactive map with one marker per trip stop, sized by duration."""
    fig = go.Figure()

    year_stops = {}
    for trip in timeline["trips"]:
        year = trip["departure_date"][:4]
        if year not in year_stops:
            year_stops[year] = []
        for stop in trip["stops"]:
            year_stops[year].append({
                "lat": stop["coordinates"]["lat"],
                "lon": stop["coordinates"]["lon"],
                "city": stop["city"],
                "country": stop["country"],
                "days": stop["days"],
                "date": stop["arrival_date"],
                "trip_cities": ", ".join(trip["cities"]),
            })

    for i, year in enumerate(sorted(year_stops)):
        stops = year_stops[year]
        color = YEAR_COLORS[i % len(YEAR_COLORS)]
        fig.add_trace(go.Scattermap(
            lat=[s["lat"] for s in stops],
            lon=[s["lon"] for s in stops],
            mode="markers",
            marker=dict(
                size=[max(8, min(s["days"] * 3, 30)) for s in stops],
                color=color, opacity=0.8,
            ),
            name=year,
            text=[
                f"<b>{s['city']}, {s['country']}</b><br>"
                f"{s['date']} · {s['days']}d<br>"
                f"Trip: {s['trip_cities']}"
                for s in stops
            ],
            hoverinfo="text",
        ))

    home = timeline["home_base"]
    fig.update_layout(
        map=dict(
            style="carto-positron",
            center=dict(lat=home["center"]["lat"], lon=home["center"]["lon"]),
            zoom=2.5,
        ),
        margin=dict(l=0, r=0, t=0, b=0),
        height=450,
        legend=dict(
            orientation="h", yanchor="top", y=0.99, xanchor="left", x=0.01,
            bgcolor="rgba(0,0,0,0.5)", font=dict(color="white"),
        ),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
    )
    return fig.to_html(full_html=False, include_plotlyjs=False)


def _format_date_short(iso_date):
    """Format date as 'Feb 2020'."""
    d = datetime.fromisoformat(iso_date)
    return d.strftime("%b %Y")


def _format_date_range(dep, ret):
    """Format trip dates: 'Feb 20 – 24' or 'Feb 20 – Mar 2'."""
    d = datetime.fromisoformat(dep)
    r = datetime.fromisoformat(ret)
    if d.month == r.month:
        return f"{d.strftime('%b %d')} – {r.day}"
    return f"{d.strftime('%b %d')} – {r.strftime('%b %d')}"


def _build_stamps(timeline):
    """Build stamp data for each trip — compact Airbnb-style badges."""
    stamps = []
    for trip in timeline["trips"]:
        # Primary label: city for single-city, country for multi-city
        if len(trip["cities"]) == 1:
            label = trip["cities"][0]
        elif len(trip["countries"]) == 1:
            label = " → ".join(trip["cities"][:3])
            if len(trip["cities"]) > 3:
                label += f" +{len(trip['cities']) - 3}"
        else:
            label = " → ".join(dict.fromkeys(trip["countries"]))

        # Country subtitle
        if len(trip["countries"]) == 1:
            country = trip["countries"][0]
        else:
            country = ", ".join(trip["countries"])

        # Country code for flag
        cc = COUNTRY_FLAGS.get(trip["countries"][0], "")

        # Stops detail for expanded view
        stops = []
        for stop in trip["stops"]:
            # Filter out districts that are same as city name (redundant)
            useful_districts = [
                d for d in stop["districts"][:3]
                if d and d != stop["city"]
            ]
            districts = ", ".join(useful_districts) if useful_districts else ""
            stops.append({
                "city": stop["city"],
                "country": stop["country"],
                "days": stop["days"],
                "districts": districts,
                "arrival": stop["arrival_date"],
            })

        stamps.append({
            "id": trip["id"],
            "label": label,
            "country": country,
            "cc": cc,
            "date_display": _format_date_short(trip["departure_date"]),
            "date_range": _format_date_range(trip["departure_date"], trip["return_date"]),
            "duration": trip["duration_days"],
            "year": int(trip["departure_date"][:4]),
            "is_multi_country": len(trip["countries"]) > 1,
            "stops": stops,
            "departure": trip["departure_date"],
        })

    return stamps


def _build_timeline_data(timeline):
    """
    Build data for the horizontal scrollable timeline.

    Returns a list of year dicts, each containing trip blocks with
    positioning info (month offset within the year).
    """
    years_data = []
    for year_summary in timeline["years"]:
        y = year_summary["year"]
        blocks = []
        for trip in timeline["trips"]:
            if int(trip["departure_date"][:4]) != y:
                continue
            dep = date.fromisoformat(trip["departure_date"])
            ret = date.fromisoformat(trip["return_date"])
            # Position: day-of-year as percentage of 365
            start_pct = round((dep.timetuple().tm_yday - 1) / 365 * 100, 1)
            width_pct = max(1.5, round(trip["duration_days"] / 365 * 100, 1))

            if len(trip["cities"]) == 1:
                short_label = trip["cities"][0]
            else:
                short_label = trip["countries"][0]

            blocks.append({
                "id": trip["id"],
                "label": short_label,
                "start_pct": start_pct,
                "width_pct": width_pct,
                "duration": trip["duration_days"],
                "is_multi_country": len(trip["countries"]) > 1,
            })

        years_data.append({
            "year": y,
            "trips_count": year_summary["trips_count"],
            "new_countries": year_summary["new_countries"],
            "blocks": blocks,
        })

    return years_data


def _build_year_groups(stamps):
    """Group stamps by year (most recent first) for the stamps grid."""
    groups = {}
    for stamp in stamps:
        y = stamp["year"]
        if y not in groups:
            groups[y] = []
        groups[y].append(stamp)
    return [{"year": y, "stamps": groups[y]} for y in sorted(groups, reverse=True)]


def _compute_story_stats(timeline):
    """Compute header-level stats."""
    s = timeline["summary"]
    home = timeline["home_base"]
    date_from = datetime.fromisoformat(timeline["date_range"]["from"])
    return {
        "total_trips": s["total_trips"],
        "countries_visited": s["countries_visited"],
        "total_days": s["total_days_traveling"],
        "since_year": date_from.year,
        "home_city": home["city"],
        "home_country": home["country"],
    }


def generate_dashboard(timeline, df, output_path):
    """Generate the travel story HTML dashboard."""
    if not timeline or not timeline.get("trips"):
        _generate_empty_dashboard(output_path)
        return

    map_div = _build_trip_map(timeline)
    stamps = _build_stamps(timeline)
    year_groups = _build_year_groups(stamps)
    timeline_data = _build_timeline_data(timeline)
    stats = _compute_story_stats(timeline)

    template_dir = os.path.join(os.path.dirname(__file__), "templates")
    env = Environment(loader=FileSystemLoader(template_dir))
    env.filters["country_flag"] = _cc_to_flag
    template = env.get_template("dashboard.html")

    html = template.render(
        map_div=map_div,
        year_groups=year_groups,
        timeline_data=timeline_data,
        stats=stats,
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Dashboard saved to: {output_path}")


def _generate_empty_dashboard(output_path):
    """Generate a simple HTML page when no data is available."""
    html = """<!DOCTYPE html>
<html><head><title>Travel Story — No Data</title>
<style>
body { background: #1a1a2e; color: #e0e0e0; font-family: system-ui;
       display: flex; align-items: center; justify-content: center;
       min-height: 100vh; margin: 0; }
.msg { text-align: center; }
h1 { color: #4ecdc4; }
</style></head><body>
<div class="msg">
<h1>No Trips Found</h1>
<p>No travel data detected from your Photos library.</p>
</div></body></html>"""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Empty dashboard saved to: {output_path}")
