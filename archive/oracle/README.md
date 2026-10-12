# oracle (archived 2026-10-12)

Go job that backfilled the sentinel archive from Copernicus STAC into atlas, superseded
by noctis's `sentinel-sync` (daily) and `sentinel-backfill` flows, which write to
ephemeris. These manifests are kept for reference only and are not applied by any
pipeline, so deleting the old completed `oracle` Job can no longer bring it back.

- Its last run (2025-12-14) is the archive data still in atlas's `imagery_finder_archiveitem`.
- Known bugs, unfixed: `limit=500` without the STAC `fields` param (CDSE rejects it for
  Sentinel-2, so S2 was never scraped), `sortby=datetime` paging skips scenes, and inserts
  don't dedupe.
- Secrets: still in cuneiform at `galaxy-kv/prod/oracle`.
- Source: the `oracle` repo.
