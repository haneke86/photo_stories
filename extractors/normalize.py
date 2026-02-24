"""
normalize.py — Shared city normalization rules.

Apple's reverse-geocoded _city field is district-level for big metros in certain
countries. These rules normalize to metro level. The same logic is ported to
Swift in CityNormalizer.swift for the iOS app.
"""

import re


# French region → metro city mapping
FRANCE_REGION_TO_METRO = {
    "Île-de-France": "Paris",
}


# Known ASCII→Unicode fixes from reverse_geocoder vs Apple data
CITY_NAME_FIXES = {
    "Mugla": "Muğla",
    "Izmir": "İzmir",
    "Canakkale": "Çanakkale",
    "Sanliurfa": "Şanlıurfa",
}


def normalize_city(country, city, state, sub_admin):
    """
    Normalize city to metro level.

    Apple's _city is district-level for big metros:
    - Turkey: _city=Beşiktaş, _state=Istanbul → use state
    - UK/Greece: _city=Hounslow, _subAdmin=London → use subAdmin
    - France: _city=Clichy, _state=Île-de-France → use state→metro mapping
    - Ireland: _city=Dublin 2 → strip postal district number
    - US/Italy/others: _city is already correct (New York, Florence)
    """
    if country == "Türkiye" and state:
        return state
    if country in ("United Kingdom", "Greece") and sub_admin:
        return sub_admin
    if country == "France" and state:
        return FRANCE_REGION_TO_METRO.get(state, city or state)
    if country == "Ireland" and city:
        return strip_postal_district(city)
    return city or sub_admin or state or "Unknown"


def strip_postal_district(city):
    """Strip postal district numbers: 'Dublin 2' → 'Dublin'."""
    m = re.match(r'^(.+?)\s+\d+$', city)
    return m.group(1) if m else city


def apply_city_name_fixes(city):
    """Fix ASCII→Unicode mismatches (e.g. 'Mugla' → 'Muğla')."""
    return CITY_NAME_FIXES.get(city, city)
