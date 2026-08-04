import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/get_access_token"

req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='GET')
try:
    with urllib.request.urlopen(req, context=ctx) as res:
        data = json.loads(res.read().decode())
        access_token = data['token']
        print("Got access token!")
except Exception as e:
    print(f"Failed to get token: {e}")
    exit(1)

# Now test the search endpoint
search_url = "https://data.rtt.io/api/v1/json/search/EUS"
print(f"Testing {search_url}")
req = urllib.request.Request(search_url, headers={'Authorization': f'Bearer {access_token}'}, method='GET')
try:
    with urllib.request.urlopen(req, context=ctx) as res:
        print(res.read().decode()[:500]) # Print first 500 chars of response
except Exception as e:
    print(f"Failed search: {e}")

