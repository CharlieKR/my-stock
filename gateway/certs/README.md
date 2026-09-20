# Supabase database CA

`supabase-prod-ca-2021.crt` is the public CA distributed by Supabase's dashboard:
https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt

The URL template is published in the official dashboard source:
https://github.com/supabase/supabase/blob/master/apps/studio/hooks/custom-content/custom-content.json

`database.mjs` adds this CA to Node's standard roots and keeps certificate and hostname verification enabled. This is a public certificate, not a private key.
