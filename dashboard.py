"""
dashboard.py — Generate a story-focused travel timeline dashboard.

Receives a timeline dict (from trips.py) and renders trip cards, a trip
map, and year summaries into an HTML file using a Jinja2 template.
"""

import json
import os
from datetime import datetime

import plotly.graph_objects as go
import plotly.express as px
from jinja2 import Environment, FileSystemLoader

# Color palette for years
YEAR_COLORS = px.colors.qualitative.Set2


def _build_trip_map(timeline):
    """
    Interactive map showing one marker per trip stop.

    Markers are sized by duration and colored by year.
    """
    fig = go.Figure()

    # Collect all stops with their trip context
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
                "photos": stop["photo_count"],
                "date": stop["arrival_date"],
                "trip_cities": ", ".join(trip["cities"]),
            })

    years = sorted(year_stops.keys())
    for i, year in enumerate(years):
        stops = year_stops[year]
        color = YEAR_COLORS[i % len(YEAR_COLORS)]

        fig.add_trace(
            go.Scattermap(
                lat=[s["lat"] for s in stops],
                lon=[s["lon"] for s in stops],
                mode="markers",
                marker=dict(
                    size=[max(8, min(s["days"] * 3, 30)) for s in stops],
                    color=color,
                    opacity=0.8,
                ),
                name=year,
                text=[
                    f"<b>{s['city']}, {s['country']}</b><br>"
                    f"{s['date']} · {s['days']}d · {s['photos']} photos<br>"
                    f"Trip: {s['trip_cities']}"
                    for s in stops
                ],
                hoverinfo="text",
            )
        )

    home = timeline["home_base"]
    fig.update_layout(
        map=dict(
            style="carto-positron",
            center=dict(lat=home["center"]["lat"], lon=home["center"]["lon"]),
            zoom=2.5,
        ),
        margin=dict(l=0, r=0, t=0, b=0),
        height=500,
        legend=dict(
            orientation="h",
            yanchor="top",
            y=0.99,
            xanchor="left",
            x=0.01,
            bgcolor="rgba(0,0,0,0.5)",
            font=dict(color="white"),
        ),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
    )

    return fig.to_html(full_html=False, include_plotlyjs=False)


def _format_date_range(dep, ret):
    """Format trip dates for display: 'Feb 20 – 24, 2020' or 'Feb 20 – Mar 2, 2020'."""
    d = datetime.fromisoformat(dep)
    r = datetime.fromisoformat(ret)
    if d.year == r.year and d.month == r.month:
        return f"{d.strftime('%b %d')} – {r.day}, {r.year}"
    elif d.year == r.year:
        return f"{d.strftime('%b %d')} – {r.strftime('%b %d')}, {r.year}"
    else:
        return f"{d.strftime('%b %d, %Y')} – {r.strftime('%b %d, %Y')}"


def _build_trip_cards(timeline):
    """Build display-ready trip card data for the template."""
    cards = []
    for trip in timeline["trips"]:
        # Primary destination: first city, or multi-city label
        if len(trip["cities"]) == 1:
            destination = trip["cities"][0]
        elif len(trip["countries"]) == 1:
            destination = " → ".join(trip["cities"][:3])
            if len(trip["cities"]) > 3:
                destination += f" +{len(trip['cities']) - 3}"
        else:
            destination = " → ".join(dict.fromkeys(trip["countries"]))

        # Subtitle: country or multi-country
        if len(trip["countries"]) == 1:
            subtitle = trip["countries"][0]
        else:
            subtitle = ", ".join(trip["countries"])

        # Stops summary
        stops_display = []
        for stop in trip["stops"]:
            districts = ", ".join(stop["districts"][:3]) if stop["districts"] else ""
            stops_display.append({
                "city": stop["city"],
                "country": stop["country"],
                "days": stop["days"],
                "districts": districts,
            })

        cards.append({
            "id": trip["id"],
            "destination": destination,
            "subtitle": subtitle,
            "date_range": _format_date_range(trip["departure_date"], trip["return_date"]),
            "duration": trip["duration_days"],
            "photo_count": trip["photo_count"],
            "stops": stops_display,
            "year": int(trip["departure_date"][:4]),
            "countries": trip["countries"],
            "is_multi_country": len(trip["countries"]) > 1,
        })

    return cards


def _build_year_sections(timeline, trip_cards):
    """Group trip cards into year sections with summary stats."""
    year_map = {}
    for year_summary in timeline["years"]:
        y = year_summary["year"]
        year_map[y] = {
            "year": y,
            "trips_count": year_summary["trips_count"],
            "countries": year_summary["countries"],
            "new_countries": year_summary["new_countries"],
            "days_abroad": year_summary["days_abroad"],
            "longest_trip": year_summary["longest_trip"],
            "trips": [],
        }

    for card in trip_cards:
        y = card["year"]
        if y in year_map:
            year_map[y]["trips"].append(card)

    return [year_map[y] for y in sorted(year_map.keys(), reverse=True)]


def _compute_story_stats(timeline):
    """Compute header-level story statistics."""
    s = timeline["summary"]
    home = timeline["home_base"]
    date_from = datetime.fromisoformat(timeline["date_range"]["from"])

    # Find longest trip
    longest = None
    for trip in timeline["trips"]:
        if longest is None or trip["duration_days"] > longest["duration_days"]:
            longest = trip

    longest_display = "N/A"
    if longest:
        dest = longest["cities"][0] if len(longest["cities"]) == 1 else "Multi-city"
        longest_display = f"{dest} ({longest['duration_days']}d)"

    return {
        "total_trips": s["total_trips"],
        "countries_visited": s["countries_visited"],
        "cities_visited": s["cities_visited"],
        "total_days": s["total_days_traveling"],
        "since_year": date_from.year,
        "home_city": home["city"],
        "home_country": home["country"],
        "longest_trip": longest_display,
    }


def generate_dashboard(timeline, df, output_path):
    """
    Generate the story-focused HTML dashboard.

    Args:
        timeline: Timeline dict from build_timeline()
        df: Original DataFrame (used for the map if needed)
        output_path: Where to write the output HTML file
    """
    if not timeline or not timeline.get("trips"):
        _generate_empty_dashboard(output_path)
        return

    map_div = _build_trip_map(timeline)
    trip_cards = _build_trip_cards(timeline)
    year_sections = _build_year_sections(timeline, trip_cards)
    stats = _compute_story_stats(timeline)

    # Render template
    template_dir = os.path.join(os.path.dirname(__file__), "templates")
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template("dashboard.html")

    html = template.render(
        map_div=map_div,
        year_sections=year_sections,
        stats=stats,
        timeline_json=json.dumps(timeline["summary"]),
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
