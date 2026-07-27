import io
import json
import urllib.request
import zipfile

manifest = json.loads(
    urllib.request.urlopen(
        "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
    ).read()
)

versions_to_check = [
    "26w14a",
    "26.3-snapshot-1",
    "26.3-snapshot-2",
    "26.3-snapshot-3",
    "1.21.5",
]

for vid in versions_to_check:
    try:
        pkg = json.loads(
            urllib.request.urlopen(
                next(v["url"] for v in manifest["versions"] if v["id"] == vid)
            ).read()
        )
        svr_url = pkg["downloads"]["server"]["url"]
        data = urllib.request.urlopen(svr_url).read()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            vj = json.loads(z.read("version.json"))
            print(f"{vid}: {vj['pack_version']}")
    except (
        OSError,
        KeyError,
        StopIteration,
        zipfile.BadZipFile,
        json.JSONDecodeError,
    ) as e:
        print(f"{vid}: ERROR {e}")
