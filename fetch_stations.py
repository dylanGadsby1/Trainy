import urllib.request
import json
import ssl

# Bypass SSL if needed
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# Query Wikidata for all items that are instances of a railway station in the UK (P17: Q145) 
# and have a CRS code (P296). Get coordinates as well (P625).
query = """
SELECT ?stationLabel ?crs ?coord WHERE {
  ?station wdt:P31/wdt:P279* wd:Q55488 .
  ?station wdt:P17 wd:Q145 .
  ?station wdt:P296 ?crs .
  ?station wdt:P625 ?coord .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
"""

url = "https://query.wikidata.org/sparql?query=" + urllib.parse.quote(query) + "&format=json"

req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        
        stations = []
        for item in data['results']['bindings']:
            name = item['stationLabel']['value']
            crs = item['crs']['value']
            coord_str = item['coord']['value']
            
            # Extract Point(lon lat)
            if coord_str.startswith("Point("):
                lon_lat = coord_str[6:-1].split(" ")
                lon = float(lon_lat[0])
                lat = float(lon_lat[1])
                stations.append({
                    "name": name,
                    "crs": crs,
                    "lat": lat,
                    "lon": lon
                })
        
        # Format for Swift
        swift_array = "let ukStations: [UKStation] = [\n"
        # Avoid duplicates by CRS
        seen_crs = set()
        
        for s in sorted(stations, key=lambda x: x['name']):
            if s['crs'] not in seen_crs:
                seen_crs.add(s['crs'])
                swift_array += f'    UKStation(name: "{s["name"]}", crs: "{s["crs"]}", coordinate: CLLocationCoordinate2D(latitude: {s["lat"]}, longitude: {s["lon"]})),\n'
        swift_array += "].sorted { $0.name < $1.name }\n"
        
        with open("ukStations_generated.swift", "w") as f:
            f.write(swift_array)
        
        print(f"Generated {len(seen_crs)} stations.")
except Exception as e:
    print("Error:", e)
