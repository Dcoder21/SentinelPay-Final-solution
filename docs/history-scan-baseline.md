# Historical scan classification

Full Git history scanning remains enabled. Four exact historical fingerprints were added to the existing baseline:

- Starter commit 14aee34463f9a418987431fade642f8cb90cccaa: three docker-compose findings are the documented local PostgreSQL training password and its URLs. These are not AWS or external provider credentials. Current compose requires a supplied password.
- Commit 5306592d1a58d28225066956e5fed3eb9cd2f7d7: one environment variable reference was misclassified despite containing no password value.

Only these historical fingerprints are covered. No broad rule or path exclusion was introduced. Baseline credential fields remain redacted. GitHub push protection remains enabled.
