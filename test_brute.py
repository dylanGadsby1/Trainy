import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/get_access_token"

req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='GET')
access_token = None
try:
    with urllib.request.urlopen(req, context=ctx) as res:
        access_token = json.loads(res.read().decode())['token']
except Exception as e:
    exit(1)

prefixes = ["/api", "/api/v1", "/api/v2", "/api/v1/json", "/v1", "/v2"]
paths = [
    "/search/EUS", "/search/gb-nr/EUS", "/gb-nr/search/EUS",
    "/departures/EUS", "/departures/gb-nr/EUS", "/gb-nr/departures/EUS",
    "/locations/EUS", "/locations/gb-nr/EUS", "/gb-nr/locations/EUS",
    "/services/EUS", "/services/gb-nr/EUS", "/gb-nr/services/EUS"
]

for p in prefixes:
    for path in paths:
        endpoint = f"https://data.rtt.io{p}{path}"
        req = urllib.request.Request(endpoint, headers={'Authorization': f'Bearer {access_token}'}, method='GET')
        try:
            with urllib.request.urlopen(req, context=ctx) as res:
                print(f"SUCCESS! {endpoint}")
                break
        except urllib.error.HTTPError as e:
            if e.code not in [404, 405, 401]:
                print(f"Found {endpoint} with code {e.code}")
        except Exception:
            pass

