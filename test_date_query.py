import urllib.request
import urllib.parse
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

endpoints = [
    "https://data.rtt.io/gb-nr/location?location=EUS&date=2026-08-02",
    "https://data.rtt.io/gb-nr/location?location=EUS&time=2026-08-02T12:00:00",
    "https://data.rtt.io/gb-nr/location?location=EUS&datetime=2026-08-02T12:00:00Z",
    "https://data.rtt.io/gb-nr/location?location=EUS&timeFrom=2026-08-02T12:00:00Z",
]

for endpoint in endpoints:
    print(f"Testing {endpoint}")
    req = urllib.request.Request(endpoint, headers={'Authorization': f'Bearer {access_token}'}, method='GET')
    try:
        with urllib.request.urlopen(req, context=ctx) as res:
            print("SUCCESS!")
            response_data = res.read().decode()
            data = json.loads(response_data)
            print("Query timeFrom:", data.get('query', {}).get('timeFrom'))
            print("Query timeTo:", data.get('query', {}).get('timeTo'))
            break
    except urllib.error.HTTPError as e:
        print(f"Failed: {e.code}")
    except Exception as e:
        print(f"Failed: {e}")
