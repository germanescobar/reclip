# S3 Public Access Setup

LoomClone supports two download modes for uploaded recordings:

- `Presigned`
  Returns a time-limited signed URL for each upload.
- `Public`
  Returns a plain S3 object URL.

For `Public` mode, the app now assumes public access is provided by bucket policy, not by per-object ACLs.

## Why

Per-object ACLs were unreliable in this bucket setup. Uploads succeeded, but objects still were not publicly readable unless access was changed manually in the AWS console.

Using a bucket policy on the `recordings/` prefix is simpler and more reliable.

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

## Apply With AWS CLI

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

## Related Bucket Settings

These bucket-level public access block settings must allow public reads:

```json
{
  "BlockPublicAcls": false,
  "IgnorePublicAcls": false,
  "BlockPublicPolicy": false,
  "RestrictPublicBuckets": false
}
```

In this project, public access is expected to come from the bucket policy above.

## App Settings

In LoomClone Settings:

- enable `Use public object URLs`
- set the correct bucket
- set the correct region

Optional:

- set `Public Base URL` if you want to use a custom domain or CDN instead of the raw S3 URL

## Verification

After uploading a recording, the returned URL should open without signing parameters or manual ACL changes.
