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

req2 = urllib.request.Request("https://data.rtt.io/gb-nr/location?location=CCH", headers={"Authorization": f"Bearer {access_token}"})
with urllib.request.urlopen(req2, context=ctx) as response:
    data = json.loads(response.read().decode())
    print(f"Number of services: {len(data.get('services', []))}")
