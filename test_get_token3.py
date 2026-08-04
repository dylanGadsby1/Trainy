import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
urls = [
    "https://data.rtt.io/api/get_access_token",
    "https://data.rtt.io/api/v1/get_access_token",
    "https://api-portal.rtt.io/api/v1/get_access_token",
    "https://api.rtt.io/api/v1/token"
]

for url in urls:
    for method in ['GET', 'POST']:
        print(f"Trying {method} {url}")
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method=method)
        try:
            with urllib.request.urlopen(req, context=ctx) as res:
                print("SUCCESS!", res.read().decode())
                break
        except Exception as e:
            print(f"Failed: {e}")

