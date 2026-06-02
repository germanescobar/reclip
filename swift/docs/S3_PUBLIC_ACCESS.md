# S3 Public Access & CDN Setup

LoomClone serves uploaded recordings as **public object URLs**. After an
upload, the app returns a plain URL to the object under the `recordings/`
prefix — either the raw S3 URL or, if a base URL is configured, a CDN URL
(e.g. a CloudFront domain).

Public access is provided by a **bucket policy**, not per-object ACLs.

## Why public URLs

Recordings are shared via link, so the player fetches them directly over HTTP.
Time-limited signed URLs were dropped because they expire, can't be cached by a
CDN (each URL is unique), and don't work cleanly behind CloudFront. A public
object under an unguessable, UUID-based key is the simpler, faster model.

Per-object ACLs were also unreliable in this bucket setup: uploads succeeded but
objects weren't publicly readable until access was changed manually in the AWS
console. A bucket policy on the `recordings/` prefix is simpler and reliable.

## Required Bucket Policy

Apply this policy to the bucket used by LoomClone uploads:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadRecordings",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::loom-clone-recordings/recordings/*"
    }
  ]
}
```

If you use a different bucket name, replace `loom-clone-recordings` with your bucket.

### Apply With AWS CLI

```bash
cat > /tmp/loomclone-public-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadRecordings",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::loom-clone-recordings/recordings/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket loom-clone-recordings \
  --policy file:///tmp/loomclone-public-policy.json \
  --region us-east-2
```

### Related Bucket Settings

These bucket-level public access block settings must allow public reads:

```json
{
  "BlockPublicAcls": false,
  "IgnorePublicAcls": false,
  "BlockPublicPolicy": false,
  "RestrictPublicBuckets": false
}
```

Public access is expected to come from the bucket policy above.

## Serving Through CloudFront (recommended)

Fetching directly from a single S3 region gives inconsistent throughput, which
shows up as mid-playback rebuffering in the web player. Putting CloudFront in
front of the bucket serves cached byte-ranges from the edge with higher, steadier
throughput.

High-level steps:

1. Create a CloudFront distribution with the S3 bucket as the origin.
   - For a public bucket, an Origin Access Control (OAC) is optional but
     recommended so the bucket can be locked to CloudFront-only access.
2. (Optional) Attach a custom domain, e.g. `cdn.reclip.click`, with an ACM
   certificate.
3. Set the app's **Public Base URL** to the CloudFront domain (see below). New
   uploads will then return `https://<cdn-domain>/recordings/<file>`.

The download URL is persisted with each recording at upload time, so changing
the base URL only affects **new** recordings. Existing rows keep their old URLs
until backfilled.

## App Settings

In LoomClone Settings, under **AWS**:

- set the correct **Bucket**
- set the correct **Region**
- set **Public Base URL (CDN, optional)** to your CloudFront domain (e.g.
  `https://cdn.reclip.click`) if you want to serve through a CDN or custom
  domain instead of the raw S3 URL

These can also be provided via environment variables:

- `S3_BUCKET`
- `AWS_REGION`
- `S3_PUBLIC_BASE_URL`

## Verification

After uploading a recording, the returned URL should open in a browser without
any signing parameters and without manual ACL changes. If a Public Base URL is
set, the URL should use that domain.
