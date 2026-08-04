import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
req = urllib.request.Request("https://data.rtt.io/api/get_access_token", headers={"Authorization": f"Bearer {refresh_token}"})
with urllib.request.urlopen(req, context=ctx) as response:
    access_token = json.loads(response.read().decode())['token']

def get_services(url):
    try:
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
        with urllib.request.urlopen(req, context=ctx) as response:
            data = json.loads(response.read().decode())
            return data.get('services', [])
    except Exception as e:
        print(f"Error fetching {url}: {e}")
        return []

# Try different parameters for filtering
print("to=HAV:", len(get_services("https://data.rtt.io/gb-nr/location?location=CCH&to=HAV")))
print("destination=HAV:", len(get_services("https://data.rtt.io/gb-nr/location?location=CCH&destination=HAV")))
print("filter=HAV:", len(get_services("https://data.rtt.io/gb-nr/location?location=CCH&filter=HAV")))
print("filterLocation=HAV:", len(get_services("https://data.rtt.io/gb-nr/location?location=CCH&filterLocation=HAV")))
print("callingAt=HAV:", len(get_services("https://data.rtt.io/gb-nr/location?location=CCH&callingAt=HAV")))

