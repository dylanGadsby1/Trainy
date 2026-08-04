import urllib.request
import urllib.parse
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/v1/token"

print("Trying https://data.rtt.io/api/v1/token with Bearer Auth")
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='POST')
try:
    with urllib.request.urlopen(req, context=ctx) as res:
        print(res.read().decode())
except Exception as e:
    print(f"Failed: {e}")

url2 = "https://api.rtt.io/api/v1/token"
print("Trying https://api.rtt.io/api/v1/token with Bearer Auth")
req = urllib.request.Request(url2, headers={'Authorization': f'Bearer {refresh_token}'}, method='POST')
try:
    with urllib.request.urlopen(req, context=ctx) as res:
        print(res.read().decode())
except Exception as e:
    print(f"Failed: {e}")

