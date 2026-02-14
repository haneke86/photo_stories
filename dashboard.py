"""
dashboard.py — Generate an interactive HTML dashboard from photo location data.

Builds Plotly visualizations (map, charts, timeline) and assembles them into
a single HTML file using a Jinja2 template.
"""

import os

import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
from jinja2 import Environment, FileSystemLoader

# Consistent color palette for years
YEAR_COLORS = px.colors.qualitative.Set2


def _build_map(df):
    """Interactive world map with photo markers colored by year."""
    df_map = df.copy()
    df_map["year_str"] = df_map["year"].astype(str)

    fig = go.Figure()

    years = sorted(df_map["year_str"].unique())
    for i, year in enumerate(years):
        subset = df_map[df_map["year_str"] == year]
        color = YEAR_COLORS[i % len(YEAR_COLORS)]

        fig.add_trace(
            go.Scattermap(
                lat=subset["latitude"],
                lon=subset["longitude"],
                mode="markers",
                marker=dict(size=6, color=color, opacity=0.7),
                name=year,
                text=subset.apply(
                    lambda r: (
                        f"{r['city']}, {r['country']}<br>"
                        f"{r['date'].strftime('%Y-%m-%d')}<br>"
                        f"{r['filename']}"
                    ),
                    axis=1,
                ),
                hoverinfo="text",
            )
        )

    fig.update_layout(
        map=dict(
            style="carto-positron",
            center=dict(
                lat=df["latitude"].mean(),
                lon=df["longitude"].mean(),
            ),
            zoom=1.5,
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


def _build_countries_chart(df):
    """Horizontal bar chart of top 20 countries by photo count."""
    counts = df.groupby("country").size().nlargest(20).sort_values()

    fig = go.Figure(
        go.Bar(
            y=counts.index,
            x=counts.values,
            orientation="h",
            marker_color="#4ecdc4",
        )
    )
    fig.update_layout(
        title="Top Countries by Photo Count",
        xaxis_title="Photos",
        yaxis_title="",
        height=max(400, len(counts) * 25),
        margin=dict(l=10, r=10, t=40, b=30),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#e0e0e0"),
        xaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
        yaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
    )

    return fig.to_html(full_html=False, include_plotlyjs=False)


def _build_cities_chart(df):
    """Horizontal bar chart of top 20 cities by photo count."""
    counts = df.groupby("city").size().nlargest(20).sort_values()

    fig = go.Figure(
        go.Bar(
            y=counts.index,
            x=counts.values,
            orientation="h",
            marker_color="#ff6b6b",
        )
    )
    fig.update_layout(
        title="Top Cities by Photo Count",
        xaxis_title="Photos",
        yaxis_title="",
        height=max(400, len(counts) * 25),
        margin=dict(l=10, r=10, t=40, b=30),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#e0e0e0"),
        xaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
        yaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
    )

    return fig.to_html(full_html=False, include_plotlyjs=False)


def _build_timeline(df):
    """Monthly timeline showing photo count over time."""
    monthly = df.groupby("month").size().reset_index(name="count")
    monthly["month"] = pd.to_datetime(monthly["month"])
    monthly = monthly.sort_values("month")

    fig = go.Figure(
        go.Scatter(
            x=monthly["month"],
            y=monthly["count"],
            mode="lines+markers",
            line=dict(color="#ffe66d", width=2),
            marker=dict(size=5),
            fill="tozeroy",
            fillcolor="rgba(255,230,109,0.1)",
        )
    )
    fig.update_layout(
        title="Monthly Photo Timeline",
        xaxis_title="",
        yaxis_title="Photos",
        height=350,
        margin=dict(l=10, r=10, t=40, b=30),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#e0e0e0"),
        xaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
        yaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
    )

    return fig.to_html(full_html=False, include_plotlyjs=False)


def _build_yearly_breakdown(df):
    """Stacked bar chart: year × country (top countries only)."""
    # Limit to top 10 countries to keep chart readable
    top_countries = df["country"].value_counts().nlargest(10).index.tolist()
    df_top = df[df["country"].isin(top_countries)].copy()

    pivot = df_top.groupby(["year", "country"]).size().unstack(fill_value=0)

    fig = go.Figure()
    colors = YEAR_COLORS
    for i, country in enumerate(pivot.columns):
        fig.add_trace(
            go.Bar(
                x=pivot.index.astype(str),
                y=pivot[country],
                name=country,
                marker_color=colors[i % len(colors)],
            )
        )

    fig.update_layout(
        barmode="stack",
        title="Yearly Breakdown by Country",
        xaxis_title="Year",
        yaxis_title="Photos",
        height=400,
        margin=dict(l=10, r=10, t=40, b=30),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#e0e0e0"),
        xaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
        yaxis=dict(gridcolor="rgba(255,255,255,0.1)"),
        legend=dict(
            bgcolor="rgba(0,0,0,0.3)",
            font=dict(color="white"),
        ),
    )

    return fig.to_html(full_html=False, include_plotlyjs=False)


def _compute_stats(df):
    """Compute summary statistics for the dashboard cards."""
    total_photos = len(df)
    total_countries = df["country"].nunique()
    total_cities = df["city"].nunique()

    # Most-visited country
    top_country = df["country"].mode().iloc[0] if total_photos > 0 else "N/A"
    top_country_count = (df["country"] == top_country).sum()

    # Busiest travel month
    if total_photos > 0:
        busiest_month = df["month"].mode().iloc[0]
        busiest_month_count = (df["month"] == busiest_month).sum()
    else:
        busiest_month = "N/A"
        busiest_month_count = 0

    # Date range
    if total_photos > 0:
        date_min = df["date"].min().strftime("%b %Y")
        date_max = df["date"].max().strftime("%b %Y")
        date_range = f"{date_min} — {date_max}"
    else:
        date_range = "N/A"

    return {
        "total_photos": f"{total_photos:,}",
        "total_countries": total_countries,
        "total_cities": total_cities,
        "top_country": top_country,
        "top_country_count": f"{top_country_count:,}",
        "busiest_month": busiest_month,
        "busiest_month_count": f"{busiest_month_count:,}",
        "date_range": date_range,
    }


def generate_dashboard(df, output_path):
    """
    Generate the complete HTML dashboard.

    Args:
        df: DataFrame from extract_photo_data()
        output_path: Where to write the output HTML file
    """
    if df.empty:
        _generate_empty_dashboard(output_path)
        return

    # Build all visualization components
    map_div = _build_map(df)
    countries_chart = _build_countries_chart(df)
    cities_chart = _build_cities_chart(df)
    timeline_chart = _build_timeline(df)
    yearly_chart = _build_yearly_breakdown(df)
    stats = _compute_stats(df)

    # Render template
    template_dir = os.path.join(os.path.dirname(__file__), "templates")
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template("dashboard.html")

    html = template.render(
        map_div=map_div,
        countries_chart=countries_chart,
        cities_chart=cities_chart,
        timeline_chart=timeline_chart,
        yearly_chart=yearly_chart,
        stats=stats,
    )

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"Dashboard saved to: {output_path}")


def _generate_empty_dashboard(output_path):
    """Generate a simple HTML page when no data is available."""
    html = """<!DOCTYPE html>
<html><head><title>Travel Dashboard — No Data</title>
<style>
body { background: #1a1a2e; color: #e0e0e0; font-family: system-ui;
       display: flex; align-items: center; justify-content: center;
       min-height: 100vh; margin: 0; }
.msg { text-align: center; }
h1 { color: #4ecdc4; }
</style></head><body>
<div class="msg">
<h1>No Geotagged Photos Found</h1>
<p>No photos with GPS data were found in the last 6 years.</p>
<p>Make sure your Photos library contains geotagged photos.</p>
</div></body></html>"""

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"Empty dashboard saved to: {output_path}")
