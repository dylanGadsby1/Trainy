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

url = "https://data.rtt.io/gb-nr/service/C82647/2026-08-02"
try:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
    with urllib.request.urlopen(req, context=ctx) as response:
        print(f"Success fetching {url}!")
        service_data = json.loads(response.read().decode())
        print("Keys:", list(service_data.keys()))
        print("Calls:", len(service_data.get('calls', [])))
except Exception as e:
    print(f"Failed {url}: {e}")
