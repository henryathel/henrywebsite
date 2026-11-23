# The random face on the landing page.
#
# The pool is generated elsewhere and uploaded with scripts/upload-faces.sh as
# faces/000.jpg, faces/001.jpg, ... in the site bucket. A CloudFront Function can't list
# S3, so the pool size is read from the bucket here and baked into the function: upload
# first, then apply (docs/decisions.md #23).

data "aws_s3_objects" "faces" {
  bucket   = var.bucket_name
  prefix   = "faces/"
  max_keys = 1000
}

locals {
  face_keys  = sort(data.aws_s3_objects.faces.keys)
  face_count = length(local.face_keys)

  # Numbering must run from 000 with no gaps, since the function picks a number, not a key.
  expected_keys = [for i in range(local.face_count) : format("faces/%03d.jpg", i)]
}

resource "aws_cloudfront_function" "random_face" {
  name    = "${var.project}-random-face"
  comment = "Rewrites /img/henry-ashton.jpg to a random face from the pool"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/functions/random-face.js", {
    face_count = local.face_count
  })

  lifecycle {
    precondition {
      condition     = join(",", local.face_keys) == join(",", local.expected_keys) && local.face_count < 1000
      error_message = "The face pool must be faces/000.jpg to faces/NNN.jpg with no gaps or other keys, and fewer than 1000 faces. Upload it with scripts/upload-faces.sh."
    }
  }
}
