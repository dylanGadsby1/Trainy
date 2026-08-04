import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

urls = [
    "https://realtimetrains.github.io/api-specification/specification/paths.yml",
    "https://realtimetrains.github.io/api-specification/specification/paths/search.yml",
    "https://realtimetrains.github.io/api-specification/specification/paths.yaml"
]

for url in urls:
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req, context=ctx) as res:
            print(f"FOUND: {url}")
    except Exception as e:
        pass
